package hxunity.yaml;

import haxe.Int64;

/**
	A parsed Unity YAML file: the `%YAML` / `%TAG` preamble followed by a stream
	of `--- !u!` documents.

	The preamble and the line ending style are kept from the original text, so a
	file that is read and written back keeps its `\r\n` endings and stays
	byte-identical apart from the changes the caller actually made. That matters
	because Unity rewrites the whole file when it saves, and a tool that
	normalises line endings shows up in version control as a full file change.
**/
class UnityDocumentSet
{
	/** Directives written before the first document, in file order. **/
	public var preamble(default, null):Array<String>;

	/** Documents, in file order. **/
	public var documents(default, null):Array<UnityYamlDocument>;

	/** Line ending detected in the source, either `\n` or `\r\n`. **/
	public var lineEnding(default, null):String;

	/** True when the source ended with a line ending. **/
	public var trailingNewline(default, null):Bool;

	/** Index from file id to document, for resolving `{fileID: ...}` references. **/
	var byFileId:Map<String, UnityYamlDocument>;

	public function new(preamble:Array<String> = null, documents:Array<UnityYamlDocument> = null, lineEnding:String = "\n",
			trailingNewline:Bool = true)
	{
		this.preamble = preamble == null ? [] : preamble;
		this.documents = documents == null ? [] : documents;
		this.lineEnding = lineEnding;
		this.trailingNewline = trailingNewline;
		this.byFileId = new Map();
		reindex();
	}

	/**
		Parses [text] into a document set.

		A file with no `--- !u!` header at all (a `.meta` file, or a hand written
		fixture) still yields one document whose class id is 0 and whose body is
		whatever the file contained, so nothing is silently dropped.
	**/
	public static function parse(text:String, ?options:YamlParseOptions):UnityDocumentSet
	{
		var lineEnding = Strings.detectLineEnding(text);
		var trailing = text.length > 0 && (StringTools.endsWith(text, "\n") || StringTools.endsWith(text, "\r"));
		var preamble = [];
		// The preamble is only ever `%`-directives at the very start of the file.
		for (line in Strings.splitLines(text))
		{
			var trimmed = StringTools.trim(line);
			if (trimmed.length == 0) continue;
			if (trimmed.charAt(0) != "%") break;
			preamble.push(trimmed);
		}
		var documents = YamlParser.parseAll(text, options);
		return new UnityDocumentSet(preamble, documents, lineEnding, trailing);
	}

	/** Documents in file order, read-only view. **/
	public function count():Int
	{
		return documents.length;
	}

	/** Document at [index], or `null` when out of range. **/
	public function at(index:Int):UnityYamlDocument
	{
		return (index < 0 || index >= documents.length) ? null : documents[index];
	}

	/** First document whose class id is [classId], or `null`. **/
	public function firstOfClass(classId:Int):UnityYamlDocument
	{
		for (document in documents)
		{
			if (document.classId == classId) return document;
		}
		return null;
	}

	/** Every document whose class id is [classId], in file order. **/
	public function allOfClass(classId:Int):Array<UnityYamlDocument>
	{
		var out = [];
		for (document in documents)
		{
			if (document.classId == classId) out.push(document);
		}
		return out;
	}

	/**
		Document anchored with [fileId], or `null`.

		This is how a `{fileID: 12345}` reference inside the file is resolved: the
		value names the `&12345` anchor of some document.
	**/
	public function byId(fileId:Int64):UnityYamlDocument
	{
		if (fileId == null) return null;
		return byFileId.get(Int64.toStr(fileId));
	}

	/** Document anchored with the id in [fileIdText], or `null`. **/
	public function byIdText(fileIdText:String):UnityYamlDocument
	{
		return fileIdText == null ? null : byFileId.get(fileIdText);
	}

	/** Appends [document] and indexes it. **/
	public function add(document:UnityYamlDocument):UnityYamlDocument
	{
		documents.push(document);
		byFileId.set(Int64.toStr(document.fileId), document);
		return document;
	}

	/** Inserts [document] at [index] and indexes it. **/
	public function insert(index:Int, document:UnityYamlDocument):UnityYamlDocument
	{
		var at = index < 0 ? 0 : (index > documents.length ? documents.length : index);
		documents.insert(at, document);
		byFileId.set(Int64.toStr(document.fileId), document);
		return document;
	}

	/** Removes [document] and returns true when it was present. **/
	public function remove(document:UnityYamlDocument):Bool
	{
		var index = documents.indexOf(document);
		if (index < 0) return false;
		documents.splice(index, 1);
		byFileId.remove(Int64.toStr(document.fileId));
		return true;
	}

	/** Replaces the document anchored with [fileId], or appends it. **/
	public function replace(document:UnityYamlDocument):Void
	{
		for (i in 0...documents.length)
		{
			if (Int64.compare(documents[i].fileId, document.fileId) == 0)
			{
				documents[i] = document;
				byFileId.set(Int64.toStr(document.fileId), document);
				return;
			}
		}
		add(document);
	}

	/** Rebuilds the id index; call after mutating a document's file id. **/
	public function reindex():Void
	{
		byFileId = new Map();
		for (document in documents)
		{
			byFileId.set(Int64.toStr(document.fileId), document);
		}
	}

	/** True when [fileId] is already used by a document in this file. **/
	public function contains(fileId:Int64):Bool
	{
		return fileId != null && byFileId.exists(Int64.toStr(fileId));
	}

	/**
		Returns an id that is not used by any document in this file.

		Unity ids are random 64 bit values; the generator here is a
		xorshift seeded from the clock so repeated calls in one run differ, and
		collisions are checked against the index rather than hoped away.
	**/
	public function newFileId():Int64
	{
		var candidate:Int64;
		var attempts = 0;
		do
		{
			candidate = generateId();
			attempts++;
		}
		while (contains(candidate) && attempts < 64);
		return candidate;
	}

	/** Current xorshift state; 1 based so the generator never reaches the zero lockup. **/
	static var seed:Int = 0;

	/**
		Next pseudorandom id.

		This is a self contained xorshift generator rather than [Std.random]: the
		standard generator is not seeded on every target, and on Neko an unseeded
		`Std.random` throws instead of returning a value, which made every edit
		that creates an object fail. Two 31 bit halves are drawn so the result is
		always a positive value below `2^62`, and [Int64.add] is used to join them
		because `Int64.ofInt` on a value above `2^30` overflows on the JavaScript
		target, where an [Int] is a double.
	**/
	static function generateId():Int64
	{
		if (seed == 0)
		{
			var fromClock = Std.int(Date.now().getTime() % 2147483646);
			if (fromClock < 0) fromClock = -fromClock;
			seed = fromClock + 1;
		}
		var high = nextBits();
		var low = nextBits();
		return Int64.add(Int64.mul(Int64.ofInt(high), Int64.ofInt(1073741824)), Int64.ofInt(low));
	}

	/** xorshift32: 31 bits of state, always at least 1. **/
	static function nextBits():Int
	{
		var x = seed;
		x ^= x << 13;
		x ^= x >>> 17;
		x ^= x << 5;
		x &= 0x7FFFFFFF;
		if (x == 0) x = 1;
		seed = x;
		return x;
	}

	/**
		Serialises the set back to Unity YAML text.

		The preamble is written first, then every document header, then the
		document body indented from column 0. [options] are passed to [YamlWriter]
		for the bodies.
	**/
	public function emit(?options:YamlWriteOptions):String
	{
		var bodyOptions:YamlWriteOptions = options == null ? {} : options;
		bodyOptions.lineEnding = "\n";
		bodyOptions.trailingNewline = false;

		var sb = new StringBuf();
		for (directive in preamble)
		{
			sb.add(directive);
			sb.add("\n");
		}
		for (document in documents)
		{
			if (document.hasHeader)
			{
				sb.add("--- !u!");
				sb.add(Std.string(document.classId));
				sb.add(" &");
				sb.add(Int64.toStr(document.fileId));
				if (document.stripped) sb.add(" stripped");
				sb.add("\n");
			}
			// The body keeps Unity's single class-name key (`GameObject:`,
			// `Transform:`, ...), so it is written whole rather than unwrapped.
			sb.add(YamlWriter.write(document.body, bodyOptions));
			sb.add("\n");
		}
		var text = sb.toString();
		if (lineEnding != "\n")
		{
			text = text.split("\n").join(lineEnding);
		}
		if (!trailingNewline && StringTools.endsWith(text, lineEnding))
		{
			text = text.substr(0, text.length - lineEnding.length);
		}
		return text;
	}

	/** Writes [path] with [emit] output, creating the file if needed. **/
	public function save(path:String, ?options:YamlWriteOptions):Void
	{
		sys.io.File.saveContent(path, emit(options));
	}
}
