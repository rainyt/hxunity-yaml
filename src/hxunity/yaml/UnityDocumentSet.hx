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

	/** True when the source started with a UTF-8 BOM, which is written back. **/
	public var hasBom(default, null):Bool;

	/** Index from file id to document, for resolving `{fileID: ...}` references. **/
	var byFileId:Map<String, UnityYamlDocument>;

	public function new(preamble:Array<String> = null, documents:Array<UnityYamlDocument> = null, lineEnding:String = "\n",
			trailingNewline:Bool = true, hasBom:Bool = false)
	{
		this.preamble = preamble == null ? [] : preamble;
		this.documents = documents == null ? [] : documents;
		this.lineEnding = lineEnding;
		this.trailingNewline = trailingNewline;
		this.hasBom = hasBom;
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
		var hasBom = text.length > 0 && text.charCodeAt(0) == 0xFEFF;
		var preamble = [];
		// The preamble is only ever `%`-directives at the very start of the file,
		// scanned here directly: splitLines would allocate one string per line of
		// the whole file just to look at the first few lines.
		{
			var n = text.length;
			var p = 0;
			while (p < n)
			{
				var j = p;
				while (j < n && (text.charCodeAt(j) == " ".code || text.charCodeAt(j) == "\t".code))
				{
					j++;
				}
				var c = j < n ? text.charCodeAt(j) : -1;
				if (c == "\n".code || c == "\r".code)
				{
					p = j;
					while (p < n && (text.charCodeAt(p) == "\n".code || text.charCodeAt(p) == "\r".code))
					{
						p++;
					}
					continue;
				}
				if (c != "%".code) break;
				var e = j;
				while (e < n && text.charCodeAt(e) != "\n".code && text.charCodeAt(e) != "\r".code)
				{
					e++;
				}
				var end = e;
				while (end > j && (text.charCodeAt(end - 1) == " ".code || text.charCodeAt(end - 1) == "\t".code))
				{
					end--;
				}
				preamble.push(text.substring(j, end));
				p = e;
				while (p < n && (text.charCodeAt(p) == "\n".code || text.charCodeAt(p) == "\r".code))
				{
					p++;
				}
			}
		}
		var documents = YamlParser.parseAll(text, options);
		return new UnityDocumentSet(preamble, documents, lineEnding, trailing, hasBom);
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
		return byIdText(Int64.toStr(fileId));
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
		byFileId.set(document.fileIdText(), document);
		return document;
	}

	/** Inserts [document] at [index] and indexes it. **/
	public function insert(index:Int, document:UnityYamlDocument):UnityYamlDocument
	{
		var at = index < 0 ? 0 : (index > documents.length ? documents.length : index);
		documents.insert(at, document);
		byFileId.set(document.fileIdText(), document);
		return document;
	}

	/** Removes [document] and returns true when it was present. **/
	public function remove(document:UnityYamlDocument):Bool
	{
		var index = documents.indexOf(document);
		if (index < 0) return false;
		documents.splice(index, 1);
		byFileId.remove(document.fileIdText());
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
				byFileId.set(document.fileIdText(), document);
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
			byFileId.set(document.fileIdText(), document);
		}
	}

	/** True when [fileId] is already used by a document in this file. **/
	public function contains(fileId:Int64):Bool
	{
		return fileId != null && containsText(Int64.toStr(fileId));
	}

	/**
		True when the id spelled [fileIdText] is already used by a document.

		This is the form the hot paths want: a reference carries the id's original
		text, so asking whether it is taken needs no `Int64.toStr`.
	**/
	public function containsText(fileIdText:String):Bool
	{
		return fileIdText != null && byFileId.exists(fileIdText);
	}

	/**
		Returns an id that is not used by any document in this file.

		Unity ids are random 64 bit values; the generator is the shared
		[Xorshift] source seeded from the clock so repeated calls in one run
		differ, and collisions are checked against the index rather than hoped
		away.
	**/
	public function newFileId():Int64
	{
		var candidate:Int64;
		var attempts = 0;
		do
		{
			candidate = Xorshift.int64();
			attempts++;
		}
		while (contains(candidate) && attempts < 64);
		return candidate;
	}

	/**
		An empty set with the standard `%YAML` / `%TAG` preamble.

		This is the starting point for a file built from nothing: a `.mat`, an
		`.asset`, or a prefab an editor generates. [UnityPrefab.createEmpty] and
		[hxunity.unity.UnityMaterial.create] are built on it, so the preamble is
		written by one place rather than by every caller.
	**/
	public static function createEmpty():UnityDocumentSet
	{
		return new UnityDocumentSet(["%YAML 1.1", "%TAG !u! tag:unity3d.com,2011:"], [], "\n", true);
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
		if (hasBom)
		{
			sb.add(String.fromCharCode(0xFEFF));
		}
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
				sb.add(document.fileIdText());
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

	/**
		Independent deep copy of the whole set: same documents, headers, preamble,
		line ending, BOM and trailing-newline state.

		Bodies are deep-cloned node trees, so a cloned set can be edited freely
		without touching the original, and a clone of an unmodified parse emits
		byte-identical text. [documents] can be added to or removed from
		afterwards without affecting the source set.
	**/
	public function clone():UnityDocumentSet
	{
		var cloned:Array<UnityYamlDocument> = [];
		for (document in documents)
		{
			cloned.push(new UnityYamlDocument(document.classId, document.fileId, document.stripped, document.body.deepClone(),
				document.documentLine, document.hasFileId, document.hasHeader, document.fileIdText()));
		}
		return new UnityDocumentSet(preamble.copy(), cloned, lineEnding, trailingNewline, hasBom);
	}
}
