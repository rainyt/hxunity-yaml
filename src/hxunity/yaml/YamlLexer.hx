package hxunity.yaml;

import haxe.Int64;

/**
	Turns Unity YAML text into a flat token stream.

	The lexer is line oriented, because that is what Unity emits: every line is
	either a directive, a `---` header, a block entry, or a continuation of a
	flow collection or quoted scalar started on an earlier line. Two shapes need
	care and are handled explicitly:

	* **wrapped flow collections** — Unity breaks long `{fileID: ..., guid: ...}`
	  mappings after a comma with `max(4, indent + 4)` spaces of continuation
	  indent, and
	* **multi line quoted scalars** — `_serializedGraph` values wrap across a
	  dozen lines with a `max(4, indent + 4)` space indent, folding the break into
	  a single space.

	Neither can be tokenised line by line, so a flow collection or quoted scalar
	that is still open at end of line continues on the next line.
**/
class YamlLexer
{
	/** 1 based line of the last token produced, for error reporting. **/
	public var line(default, null):Int;

	/** 0 based column of the last token produced. **/
	public var column(default, null):Int;

	var text:String;
	var pos:Int;
	var length:Int;
	var lineStart:Int;
	var currentLine:Int;
	var eof:Bool;

	/**
		Indentation of the line currently being read.

		Mid-line tokens such as the `{` of `m_Icon: {fileID: 0}` must report the
		line's indentation, not 0, because the parser decides "is this value part
		of the current entry?" with `token.indent > keyIndent`.
	**/
	var currentIndent:Int;

	/**
		Number of flow collections currently open, 0 in block context.

		A plain scalar only ends at `,` `}` `]` inside a flow collection. In block
		context those are ordinary content — Unity writes `propertyPath:
		AnimateDatas.Array.data[1].Child` unquoted in every PrefabInstance whose
		modification touches an array element.
	**/
	var flowDepth:Int;

	/**
		Source spelling of the quoted scalar [readScalar] produced last, between
		the quotes and with line endings normalised to `\n`; `null` for plain and
		block scalars.
	**/
	var quotedSource:String;

	/**
		Indentation of the block that owns the scalar currently being read — the
		column of its key, or of the `- ` dash for a scalar sequence item. A
		folded plain continuation must be indented deeper than this, which keeps
		`    Type: x,` + `      Cont` folding while `    Override:` on the next
		item stays a sibling key.
	**/
	var ownerIndent:Int;

	static inline var TAG_PREFIX = "!u!";

	static var DOC_START = ~/^---[ \t]+!u!(-?\d+)(?:[ \t]+&(-?\d+))?(?:[ \t]+(\w+))?[ \t]*$/;
	static var DOC_START_BARE = ~/^---[ \t]*$/;

	public function new(text:String)
	{
		// A UTF-8 BOM would otherwise become part of the first key name.
		if (text.length > 0 && text.charCodeAt(0) == 0xFEFF)
		{
			text = text.substr(1);
		}
		this.text = text;
		this.pos = 0;
		this.length = text.length;
		this.lineStart = 0;
		this.currentLine = 1;
		this.currentIndent = 0;
		this.ownerIndent = 0;
		this.flowDepth = 0;
		this.eof = false;
		this.line = 1;
		this.column = 0;
	}

	/** Next token, or an [Eof] token once the input is exhausted. **/
	public function next():YamlToken
	{
		while (true)
		{
			if (eof) return finish(new YamlToken(Eof, currentLine, 0, 0));

			// Input exhausted mid-line: the last line of a file that does not end
			// with a newline reaches here, and without this check the scalar reader
			// would keep returning empty scalars instead of reaching the end.
			if (pos >= length)
			{
				eof = true;
				continue;
			}

			// Start of a line: measure indentation, then dispatch.
			if (pos == lineStart)
			{
				var indent = skipIndent();
				currentIndent = indent;
				if (pos >= length)
				{
					eof = true;
					continue;
				}
				var c = text.charCodeAt(pos);
				if (c == "\n".code || c == "\r".code)
				{
					consumeNewline();
					continue;
				}
				if (c == "#".code)
				{
					skipToLineEnd();
					continue;
				}
				return finish(startOfLineToken(indent));
			}

			var c = text.charCodeAt(pos);
			if (c == " ".code || c == "\t".code)
			{
				pos++;
				continue;
			}
			if (c == "\n".code || c == "\r".code)
			{
				consumeNewline();
				continue;
			}
			return finish(midLineToken());
		}
		return null;
	}

	function finish(token:YamlToken):YamlToken
	{
		line = token.line;
		column = token.column;
		return token;
	}

	inline function skipIndent():Int
	{
		var start = pos;
		while (pos < length)
		{
			var c = text.charCodeAt(pos);
			if (c == " ".code || c == "\t".code)
			{
				pos++;
			}
			else
			{
				break;
			}
		}
		return countIndent(start, pos);
	}

	function countIndent(start:Int, stop:Int):Int
	{
		var n = 0;
		var i = start;
		while (i < stop)
		{
			n += text.charCodeAt(i) == "\t".code ? 2 : 1;
			i++;
		}
		return n;
	}

	/** Handles the tokens that are only legal at the start of a line. **/
	function startOfLineToken(indent:Int):YamlToken
	{
		ownerIndent = indent;

		// Document markers and dashes are decided on character checks first; only
		// an actual `---` / `...` / `%` line pays for a substring of the whole
		// line. Every ordinary line used to allocate and trim one.
		var c = text.charCodeAt(pos);
		if (c == "-".code && pos + 2 < length && text.charCodeAt(pos + 1) == "-".code && text.charCodeAt(pos + 2) == "-".code)
		{
			var remaining = substringToLineEnd();
			if (DOC_START.match(remaining))
			{
				var token = new YamlToken(DocStart, currentLine, indent, indent);
				token.text = remaining;
				token.classId = Std.parseInt(DOC_START.matched(1));
				var anchor = DOC_START.matched(2);
				token.fileId = anchor == null ? Int64.ofInt(0) : Int64.parseString(anchor);
				var flag = DOC_START.matched(3);
				token.stripped = flag == "stripped";
				skipToLineEnd();
				return token;
			}
			if (DOC_START_BARE.match(remaining))
			{
				// A plain `---` starts a document with no Unity tag, e.g. a hand
				// written fixture. The body is parsed as a normal block map.
				var token = new YamlToken(BareDocStart, currentLine, indent, indent);
				token.text = remaining;
				skipToLineEnd();
				return token;
			}
		}
		else if (c == ".".code && pos + 2 < length && text.charCodeAt(pos + 1) == ".".code && text.charCodeAt(pos + 2) == ".".code)
		{
			var remaining = substringToLineEnd();
			if (remaining == "..." || StringTools.startsWith(remaining, "... "))
			{
				var token = new YamlToken(DocEnd, currentLine, indent, indent);
				token.text = remaining;
				skipToLineEnd();
				return token;
			}
		}
		else if (c == "%".code)
		{
			var token = new YamlToken(Directive, currentLine, indent, indent);
			token.text = substringToLineEnd();
			skipToLineEnd();
			return token;
		}
		else if (c == "-".code && (pos + 1 >= length || text.charCodeAt(pos + 1) == " ".code || text.charCodeAt(pos + 1) == "\t".code))
		{
			pos = lineStart + indent + 1;
			return new YamlToken(Dash, currentLine, indent, indent);
		}

		return readEntryOrScalar(indent, indent);
	}

	/** Handles `:`, flow punctuation and scalars that continue a line. **/
	function midLineToken():YamlToken
	{
		var c = text.charCodeAt(pos);
		var indent = currentIndent;
		switch (c)
		{
			case "[".code:
				pos++;
				flowDepth++;
				return new YamlToken(FlowSeqStart, currentLine, pos - 1 - lineStart, indent);
			case "]".code:
				pos++;
				if (flowDepth > 0) flowDepth--;
				return new YamlToken(FlowSeqEnd, currentLine, pos - 1 - lineStart, indent);
			case "{".code:
				pos++;
				flowDepth++;
				return new YamlToken(FlowMapStart, currentLine, pos - 1 - lineStart, indent);
			case "}".code:
				pos++;
				if (flowDepth > 0) flowDepth--;
				return new YamlToken(FlowMapEnd, currentLine, pos - 1 - lineStart, indent);
			case ",".code:
				pos++;
				return new YamlToken(Comma, currentLine, pos - 1 - lineStart, indent);
			case ":".code:
				// `key: value` written inline inside a flow mapping.
				if (pos + 1 >= length || isFlowSpace(text.charCodeAt(pos + 1)))
				{
					pos++;
					return new YamlToken(Key, currentLine, pos - 1 - lineStart, indent);
				}
				return readScalar(indent, -1);
			default:
				return readScalar(indent, -1);
		}
	}

	inline function isFlowSpace(c:Int):Bool
	{
		return c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code || c == ",".code || c == "}".code || c == "]".code;
	}

	/**
		Reads either a block key (`name:` at [keyColumn]) or a scalar value.

		[textColumn] is the column the scalar text starts at, used so a `:` inside
		URLs or times is not mistaken for a key separator.
	**/
	function readEntryOrScalar(indent:Int, textColumn:Int):YamlToken
	{
		var start = pos;
		var first = pos < length ? text.charCodeAt(pos) : -1;

		// A quoted key: `''` in every plugin importer's `platformData` block, or
		// any key Unity had to quote. The quoted text is the key when a `: `
		// separator follows on the same line; otherwise it is a scalar value.
		if (first == "'".code || first == "\"".code)
		{
			quotedSource = null;
			var keyText = first == "'".code ? readSingleQuoted() : readDoubleQuoted();
			var keyKind:ScalarKind = first == "'".code ? SingleQuoted : DoubleQuoted;
			var source = quotedSource;
			var lineEnd = pos;
			while (lineEnd < length && text.charCodeAt(lineEnd) != "\n".code && text.charCodeAt(lineEnd) != "\r".code)
			{
				lineEnd++;
			}
			var j = pos;
			while (j < lineEnd && text.charCodeAt(j) == " ".code)
			{
				j++;
			}
			if (j < lineEnd && text.charCodeAt(j) == ":".code && (j + 1 >= lineEnd || isFlowSpace(text.charCodeAt(j + 1))))
			{
				var token = new YamlToken(Key, currentLine, textColumn, indent);
				token.text = keyText;
				token.kind = keyKind;
				token.rawQuoted = source;
				token.colonSpace = colonHasSpace(j + 1);
				ownerIndent = textColumn;
				pos = j + 1;
				return token;
			}
			var scalar = new YamlToken(Scalar, currentLine, textColumn, indent);
			scalar.text = keyText;
			scalar.kind = keyKind;
			scalar.rawQuoted = source;
			return scalar;
		}

		var keyEnd = findKeySeparator();
		if (keyEnd >= 0)
		{
			var keyText = text.substring(start, keyEnd);
			if (keyText.length > 0)
			{
				var token = new YamlToken(Key, currentLine, textColumn, indent);
				token.text = keyText;
				token.colonSpace = colonHasSpace(keyEnd + 1);
				ownerIndent = textColumn;
				pos = keyEnd + 1;
				return token;
			}
		}
		return readScalar(indent, textColumn);
	}

	/**
		True when at least one space follows the key separator before the value or
		the end of the line. `value: ` and `userData:` differ exactly here.
	**/
	function colonHasSpace(after:Int):Bool
	{
		var sawSpace = false;
		var i = after;
		while (i < length)
		{
			var c = text.charCodeAt(i);
			if (c == " ".code || c == "\t".code)
			{
				sawSpace = true;
				i++;
				continue;
			}
			break;
		}
		return sawSpace;
	}

	/**
		Index of the `:` that ends a block key on the current line, or -1.

	A `:` ends a key when it is followed by a space or by end of line. Quoted
		text is skipped so `"a: b": 1` and `'{"a": 1}'` stay intact.
	**/
	function findKeySeparator():Int
	{
		var i = pos;
		if (i < length)
		{
			var c = text.charCodeAt(i);
			if (c == "'".code)
			{
				return -1; // a quoted scalar is never a key in Unity output
			}
			if (c == "\"".code)
			{
				return -1;
			}
		}
		while (i < length)
		{
			var c = text.charCodeAt(i);
			if (c == "\n".code || c == "\r".code) return -1;
			if (c == "#".code && i > pos && text.charCodeAt(i - 1) == " ".code) return -1;
			if (c == ":".code)
			{
				var next = i + 1;
				if (next >= length) return i;
				var nc = text.charCodeAt(next);
				if (nc == " ".code || nc == "\t".code || nc == "\n".code || nc == "\r".code) return i;
			}
			i++;
		}
		return -1;
	}

	/**
		Reads a scalar that may span several lines.

		Handles plain text (stopping at a flow indicator or comment), `'...'` with
		YAML folding, `"..."` with escapes, and `|` / `>` block scalars.
	**/
	function readScalar(indent:Int, textColumn:Int):YamlToken
	{
		var token = new YamlToken(Scalar, currentLine, textColumn < 0 ? pos - lineStart : textColumn, indent);
		var start = pos;
		var first = pos < length ? text.charCodeAt(pos) : -1;
		quotedSource = null;

		if (first == "'".code)
		{
			var value = readSingleQuoted();
			token.text = value;
			token.kind = SingleQuoted;
			token.rawQuoted = quotedSource;
			return token;
		}
		if (first == "\"".code)
		{
			var value = readDoubleQuoted();
			token.text = value;
			token.kind = DoubleQuoted;
			token.rawQuoted = quotedSource;
			return token;
		}

		// Explicit tag written on a value, e.g. `!u!114` or `!!str`.
		if (first == "!".code)
		{
			var tagEnd = pos;
			while (tagEnd < length && !isFlowSpace(text.charCodeAt(tagEnd)) && text.charCodeAt(tagEnd) != "#".code)
			{
				tagEnd++;
			}
			token.tag = text.substring(pos, tagEnd);
			pos = tagEnd;
			skipInlineSpaces();
			if (pos >= length || text.charCodeAt(pos) == "\n".code || text.charCodeAt(pos) == "\r".code)
			{
				token.text = "";
				token.kind = Plain;
				return token;
			}
			start = pos;
			first = text.charCodeAt(pos);
		}

		// Anchor / alias.
		if (first == "&".code || first == "*".code)
		{
			var nameEnd = pos + 1;
			while (nameEnd < length && !isFlowSpace(text.charCodeAt(nameEnd)))
			{
				nameEnd++;
			}
			var name = text.substring(pos + 1, nameEnd);
			if (first == "&".code)
			{
				token.anchor = name;
			}
			else
			{
				token.alias = name;
			}
			pos = nameEnd;
			return token;
		}

		// Block scalars.
		if ((first == "|".code || first == ">".code) && isBlockHeaderEnd(pos + 1))
		{
			var isLiteral = first == "|".code;
			pos++;
			var chomp = "";
			var explicitIndent = -1;
			while (pos < length)
			{
				var c = text.charCodeAt(pos);
				if (c == "+".code || c == "-".code)
				{
					chomp = text.charAt(pos);
					pos++;
				}
				else if (c >= "1".code && c <= "9".code)
				{
					explicitIndent = c - "0".code;
					pos++;
				}
				else
				{
					break;
				}
			}
			skipToLineEnd();
			readBlockScalar(token, isLiteral, chomp, explicitIndent, indent);
			return token;
		}

		// Plain scalar: runs to end of line, or to a flow indicator in flow context.
		// In block context a deeper-indented following line folds into the scalar —
		// Unity's managed writer wraps long plain values such as assembly names
		// exactly like that, and YAML folds the break back into one space.
		var foldedLines:Array<String> = null;
		var firstEnd = -1;
		var lastEnd = pos;
		while (true)
		{
			var end = pos;
			var atLineEnd = false;
			while (end < length)
			{
				var c = text.charCodeAt(end);
				if (c == "\n".code || c == "\r".code)
				{
					atLineEnd = true;
					break;
				}
				if (flowDepth > 0 && (c == ",".code || c == "}".code || c == "]".code))
				{
					// Inside a flow collection these terminate the scalar. In block
					// context they are ordinary content: Unity writes property paths
					// such as `Anim.Array.data[1]` and names such as `a,b` unquoted.
					break;
				}
				if (foldedLines == null && c == ":".code && end > pos && isFlowSpace(end + 1 >= length ? c : text.charCodeAt(end + 1)))
				{
					// `fileID: 0` inside `{...}` reached the value reader because the
					// lexer treated the whole fragment as a scalar. Stop at the `:` and
					// report the text before it as the key, so the mapping parser sees
					// a key followed by its value. Only on the first line: a folded
					// continuation line is content, whatever it contains.
					var keyText = StringTools.rtrim(text.substring(start, end));
					ownerIndent = end - lineStart;
					pos = end + 1;
					var keyToken = new YamlToken(Key, currentLine, end - lineStart, indent);
					keyToken.text = keyText;
					return keyToken;
				}
				if (c == "#".code && end > pos && text.charCodeAt(end - 1) == " ".code) break;
				end++;
			}
			lastEnd = end;
			if (firstEnd < 0) firstEnd = end;
			if (!atLineEnd || end >= length)
			{
				pos = end;
				break;
			}
			// 行尾：下一行更深缩进且不是文档标记或空行时折入。缩进不够与空行
			// 这两种常见情况用零分配的判断直接排除，不再为每行 substring。
			var savedPos = pos;
			var savedLine = currentLine;
			var savedLineStart = lineStart;
			pos = end;
			consumeNewline();
			var nextIndent = skipIndent();
			var atBlank = pos >= length || text.charCodeAt(pos) == "\n".code || text.charCodeAt(pos) == "\r".code;
			if (nextIndent <= ownerIndent || atBlank)
			{
				pos = savedPos;
				currentLine = savedLine;
				lineStart = savedLineStart;
				break;
			}
			var lineEnd = pos;
			while (lineEnd < length && text.charCodeAt(lineEnd) != "\n".code && text.charCodeAt(lineEnd) != "\r".code)
			{
				lineEnd++;
			}
			var content = StringTools.rtrim(text.substring(pos, lineEnd));
			if (content == "---" || StringTools.startsWith(content, "--- ") || content == "..."
				|| StringTools.startsWith(content, "... ") || StringTools.startsWith(content, "%"))
			{
				pos = savedPos;
				currentLine = savedLine;
				lineStart = savedLineStart;
				break;
			}
			if (foldedLines == null) foldedLines = [];
			foldedLines.push(content);
			pos = lineEnd;
		}
		token.kind = Plain;
		if (foldedLines == null)
		{
			token.text = StringTools.rtrim(text.substring(start, lastEnd));
			pos = lastEnd;
			return token;
		}
		// 值 = 各行以空格连接（YAML 折叠规则）；原文段整段保留，写出端按原样重放折行。
		var pieces = [StringTools.rtrim(text.substring(start, firstEnd))];
		for (folded in foldedLines)
		{
			pieces.push(folded);
		}
		token.text = pieces.join(" ");
		token.rawQuoted = normalizeSegment(start, lastEnd);
		pos = lastEnd;
		return token;
	}

	inline function isBlockHeaderEnd(at:Int):Bool
	{
		if (at >= length) return true;
		var c = text.charCodeAt(at);
		return c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code || c == "+".code || c == "-".code
			|| (c >= "1".code && c <= "9".code);
	}

	/**
		Reads a `|` or `>` block scalar.

		Unity does not emit these, but supporting them keeps the reader usable for
		hand written fixtures and for `TextAsset` bodies pasted into a prefab. The
		body is assigned to `token` so the caller can keep the token it already
		started building.
	**/
	function readBlockScalar(token:YamlToken, literal:Bool, chomp:String, explicitIndent:Int, parentIndent:Int):Void
	{
		var blockIndent = explicitIndent >= 0 ? parentIndent + explicitIndent : -1;
		var lines = [];
		var trailingBreak = false;

		// The header's own line ending is not part of the value. Consuming it here
		// is what keeps a leading blank line out of the result.
		if (pos < length && (text.charCodeAt(pos) == "\n".code || text.charCodeAt(pos) == "\r".code))
		{
			consumeNewline();
		}

		while (pos < length)
		{
			var saved = pos;
			var saveLine = currentLine;
			var saveLineStart = lineStart;
			var indent = skipIndent();
			var contentStart = pos;

			if (pos >= length)
			{
				// Trailing whitespace at end of input is not content.
				break;
			}
			var c = text.charCodeAt(pos);
			if (c == "\n".code || c == "\r".code)
			{
				consumeNewline();
				lines.push("");
				trailingBreak = true;
				continue;
			}
			if (blockIndent < 0)
			{
				if (indent <= parentIndent)
				{
					pos = saved;
					currentLine = saveLine;
					lineStart = saveLineStart;
					break;
				}
				blockIndent = indent;
			}
			if (indent < blockIndent)
			{
				pos = saved;
				currentLine = saveLine;
				lineStart = saveLineStart;
				break;
			}
			var lineEnd = pos;
			while (lineEnd < length && text.charCodeAt(lineEnd) != "\n".code && text.charCodeAt(lineEnd) != "\r".code)
			{
				lineEnd++;
			}
			// Anything indented deeper than the block indent is extra content.
			lines.push(Strings.spaces(indent - blockIndent) + text.substring(contentStart, lineEnd));
			pos = lineEnd;
			if (pos < length)
			{
				consumeNewline();
				trailingBreak = true;
			}
			else
			{
				trailingBreak = false;
			}
		}

		var body = literal ? lines.join("\n") : foldLines(lines);
		token.text = applyChomp(body, chomp, trailingBreak);
		token.kind = literal ? Literal : Folded;
	}

	function foldLines(lines:Array<String>):String
	{
		var sb = new StringBuf();
		for (i in 0...lines.length)
		{
			var line = lines[i];
			if (i > 0)
			{
				var prev = lines[i - 1];
				if (prev == "" || line == "" || StringTools.startsWith(line, " ") || StringTools.startsWith(prev, " "))
				{
					sb.add("\n");
				}
				else
				{
					sb.add(" ");
				}
			}
			sb.add(line);
		}
		return sb.toString();
	}

	/**
		Applies the block scalar's chomping indicator.

		`-` strips every trailing break, `+` keeps them all, and the default clips
		to exactly one, which is the rule a hand written fixture with `key: |`
		expects.
	**/
	function applyChomp(body:String, chomp:String, trailingBreak:Bool):String
	{
		var stripped = StringTools.rtrim(body);
		switch (chomp)
		{
			case "-":
				return stripped;
			case "+":
				return body;
			default:
				if (!trailingBreak) return stripped;
				return stripped.length == 0 ? "\n" : stripped + "\n";
		}
	}

	/** Reads a single quoted scalar, folding line breaks into spaces. **/
	function readSingleQuoted():String
	{
		pos++; // opening quote
		var segmentStart = pos;
		var sb = new StringBuf();
		var pendingBreaks = 0;
		var sawContent = false;
		while (pos < length)
		{
			var c = text.charCodeAt(pos);
			if (c == "'".code)
			{
				if (pos + 1 < length && text.charCodeAt(pos + 1) == "'".code)
				{
					sb.add("'");
					pos += 2;
					sawContent = true;
					continue;
				}
				quotedSource = normalizeSegment(segmentStart, pos);
				pos++;
				break;
			}
			if (c == "\n".code || c == "\r".code)
			{
				consumeNewline();
				pendingBreaks++;
				continue;
			}
			if (pendingBreaks > 0)
			{
				foldBreaks(sb, pendingBreaks, sawContent);
				pendingBreaks = 0;
				// The physical continuation is indented, which is not content.
				pos = skipContinuationIndent(pos);
				continue;
			}
			sb.addChar(c);
			sawContent = true;
			pos++;
		}
		return sb.toString();
	}

	/**
		Applies YAML flow folding for [breaks] consecutive line breaks.

		One break becomes a space and each further break becomes a newline, which
		is what turns Unity's wrapped `_serializedGraph` lines back into the single
		logical string it wrote.
	**/
	static function foldBreaks(sb:StringBuf, breaks:Int, sawContent:Bool):Void
	{
		if (!sawContent || breaks <= 0) return;
		sb.add(breaks == 1 ? " " : "\n");
		var i = 1;
		while (i < breaks)
		{
			sb.add("\n");
			i++;
		}
	}

	/** Reads a double quoted scalar, decoding escapes and folding breaks. **/
	function readDoubleQuoted():String
	{
		pos++; // opening quote
		var segmentStart = pos;
		var sb = new StringBuf();
		var pendingBreaks = 0;
		var sawContent = false;
		while (pos < length)
		{
			var c = text.charCodeAt(pos);
			if (c == "\"".code)
			{
				quotedSource = normalizeSegment(segmentStart, pos);
				pos++;
				break;
			}
			if (c == "\\".code && pos + 1 < length)
			{
				var e = text.charAt(pos + 1);
				if (e == "\n" || e == "\r")
				{
					consumeNewline();
					pos = skipContinuationIndent(pos);
					pos += 0;
					continue;
				}
				pos += 2;
				switch (e)
				{
					case "0":
						sb.addChar(0);
					case "a":
						sb.addChar(7);
					case "b":
						sb.addChar(8);
					case "t":
						sb.addChar(9);
					case "n":
						sb.addChar(10);
					case "v":
						sb.addChar(11);
					case "f":
						sb.addChar(12);
					case "r":
						sb.addChar(13);
					case "e":
						sb.addChar(27);
					case " ":
						sb.add(" ");
					case "\"":
						sb.add("\"");
					case "/":
						sb.add("/");
					case "\\":
						sb.add("\\");
					case "N":
						sb.add("\u0085");
					case "_":
						sb.add("\u00A0");
					case "L":
						sb.add("\u2028");
					case "P":
						sb.add("\u2029");
					case "x":
						pos = readHexEscape(sb, pos, 2);
					case "u":
						pos = readHexEscape(sb, pos, 4);
					case "U":
						pos = readHexEscape(sb, pos, 8);
					default:
						sb.add(e);
				}
				sawContent = true;
				continue;
			}
			if (c == "\n".code || c == "\r".code)
			{
				consumeNewline();
				pendingBreaks++;
				continue;
			}
			if (pendingBreaks > 0)
			{
				foldBreaks(sb, pendingBreaks, sawContent);
				pendingBreaks = 0;
				pos = skipContinuationIndent(pos);
				continue;
			}
			sb.addChar(c);
			sawContent = true;
			pos++;
		}
		return sb.toString();
	}

	function readHexEscape(sb:StringBuf, at:Int, digits:Int):Int
	{
		var hex = text.substr(at, digits);
		if (hex.length < digits) return at + hex.length;
		var code = Std.parseInt("0x" + hex);
		if (code == null) return at + hex.length;
		if (digits <= 4)
		{
			sb.addChar(code);
		}
		else
		{
			sb.add(String.fromCharCode(code));
		}
		return at + digits;
	}

	/**
		The quoted scalar's source text between the quotes, with line endings
		normalised to `\n` so [YamlWriter] can apply the file's line ending once
		at the end without doubling the carriage returns.
	**/
	function normalizeSegment(from:Int, to:Int):String
	{
		var segment = text.substring(from, to);
		if (segment.indexOf("\r") < 0) return segment;
		return StringTools.replace(StringTools.replace(segment, "\r\n", "\n"), "\r", "\n");
	}

	/** Skips the indentation at the start of a folded continuation line. **/
	function skipContinuationIndent(from:Int):Int
	{
		var i = from;
		while (i < length)
		{
			var c = text.charCodeAt(i);
			if (c == " ".code || c == "\t".code)
			{
				i++;
			}
			else
			{
				break;
			}
		}
		return i;
	}

	inline function skipInlineSpaces():Void
	{
		while (pos < length)
		{
			var c = text.charCodeAt(pos);
			if (c == " ".code || c == "\t".code) pos++ else break;
		}
	}

	function substringToLineEnd():String
	{
		var end = pos;
		while (end < length && text.charCodeAt(end) != "\n".code && text.charCodeAt(end) != "\r".code)
		{
			end++;
		}
		return StringTools.rtrim(text.substring(pos, end));
	}

	function skipToLineEnd():Void
	{
		while (pos < length && text.charCodeAt(pos) != "\n".code && text.charCodeAt(pos) != "\r".code)
		{
			pos++;
		}
	}

	function consumeNewline():Void
	{
		if (pos < length && text.charCodeAt(pos) == "\r".code)
		{
			pos++;
			if (pos < length && text.charCodeAt(pos) == "\n".code) pos++;
		}
		else if (pos < length && text.charCodeAt(pos) == "\n".code)
		{
			pos++;
		}
		currentLine++;
		lineStart = pos;
	}
}
