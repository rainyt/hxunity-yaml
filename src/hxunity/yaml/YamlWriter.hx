package hxunity.yaml;

import haxe.Int64;

/**
	Serialises a [YamlNode] tree back to Unity YAML.

	The emitted shape matches what Unity 2022.3 writes closely enough that a
	parsed prefab can be written back without the editor reformatting the whole
	file:

	* mappings and sequences are block style with two space indentation,
	* block sequence dashes sit at the indentation of the key that owns them,
	* mappings are always flow style (`{fileID: 0}`) when Unity writes them that
	  way, because the node remembers it,
	* a flow collection wraps after the comma that lands past column
	  [flowWrapColumn] (Unity breaks at 80), with the continuation indented by
	  `max(4, owner key column + 2)`, and
	* scalar quoting style is preserved.
**/
class YamlWriter
{
	/** Plain value writer: emits every line with [options] applied. **/
	public static function write(node:YamlNode, ?options:YamlWriteOptions):String
	{
		var writer = new YamlWriter(options);
		writer.writeNode(node, 0);
		return writer.finish();
	}

	var buffer:StringBuf;
	var indentStep:Int;
	var flowLineWidth:Int;
	var flowWrapColumn:Int;
	var lineEnding:String;
	var trailingNewline:Bool;

	public function new(?options:YamlWriteOptions)
	{
		this.buffer = new StringBuf();
		this.indentStep = (options == null || options.indentStep == null) ? 2 : options.indentStep;
		this.flowLineWidth = (options == null || options.flowLineWidth == null) ? 100 : options.flowLineWidth;
		this.flowWrapColumn = (options == null || options.flowWrapColumn == null) ? 80 : options.flowWrapColumn;
		this.lineEnding = (options == null || options.lineEnding == null) ? "\n" : options.lineEnding;
		this.trailingNewline = (options == null || options.trailingNewline == null) ? true : options.trailingNewline;
	}

	/** Emitted text so far, with the trailing line ending applied. **/
	public function finish():String
	{
		var text = buffer.toString();
		if (text.length == 0) return text;
		if (trailingNewline && !StringTools.endsWith(text, lineEnding))
		{
			text += lineEnding;
		}
		return text;
	}

	/** Writes [node] at [indent] as the body of a document. **/
	public function writeNode(node:YamlNode, indent:Int):Void
	{
		if (Std.isOfType(node, YamlMap))
		{
			writeBlockMap(cast node, indent);
		}
		else if (Std.isOfType(node, YamlSeq))
		{
			writeBlockSeq(cast node, indent);
		}
		else
		{
			line(indent, scalarText(node.asScalar()));
		}
	}

	// -------------------------------------------------------------- block style

	function writeBlockMap(map:YamlMap, indent:Int):Void
	{
		if (map.flow)
		{
			writeFlowMap(map, indent);
			return;
		}
		if (map.isEmpty()) return;
		for (entry in map.entries)
		{
			writeMapEntry(indent, entry);
		}
	}

	function writeBlockSeq(seq:YamlSeq, indent:Int):Void
	{
		if (seq.flow)
		{
			writeFlowSeq(seq, indent);
			return;
		}
		for (item in seq.items)
		{
			writeBlockItem(item, indent);
		}
	}

	/**
		Writes one `- ` entry.

		A scalar or flow value goes on the dash line; a block collection starts on
		the line after the bare dash, indented past it, which is exactly how Unity
		writes `m_Component`.
	**/
	function writeBlockItem(item:YamlNode, indent:Int):Void
	{
		var contentIndent = indent + indentStep;
		if (Std.isOfType(item, YamlMap))
		{
			var map:YamlMap = cast item;
			if (map.flow)
			{
				line(indent, "- " + flowMapText(map, contentIndent + 1, continuationIndent(contentIndent)));
			}
			else if (map.isEmpty())
			{
				line(indent, "- {}");
			}
			else if (isCompactItem(map))
			{
				writeCompactItem(map, indent, contentIndent);
			}
			else
			{
				// A block map that cannot be written on the dash line, which is how
				// Unity writes `m_Modifications` entries and `m_StaticBatchInfo`.
				line(indent, "-");
				writeBlockMap(map, contentIndent);
			}
		}
		else if (Std.isOfType(item, YamlSeq))
		{
			var seq:YamlSeq = cast item;
			if (seq.flow)
			{
				line(indent, "- " + flowSeqText(seq, contentIndent + 1, continuationIndent(contentIndent)));
			}
			else if (seq.isEmpty())
			{
				line(indent, "- []");
			}
			else
			{
				line(indent, "-");
				writeBlockSeq(seq, contentIndent);
			}
		}
		else
		{
			var scalar:YamlScalar = cast item;
			var text = scalarText(scalar);
			if (text.indexOf("\n") >= 0 && scalar.verbatim == null)
			{
				line(indent, "-");
				appendText(text, contentIndent);
			}
			else
			{
				// A verbatim quoted scalar carries its original continuation
				// indentation, so its line breaks are embedded as they were.
				line(indent, "- " + text);
			}
		}
	}

	/**
		True when a sequence item mapping is written on the dash line.

		Unity writes `- component: {fileID: ...}`, `- _keyName: 1014000`,
		`- _BaseMap:` with the texture fields under it, and
		`- m_RemovedComponents: []` that way; it writes an item whose first value
		is an empty scalar on a bare dash instead. Both shapes parse back into
		the same tree, so this only decides which one to emit.
	**/
	function isCompactItem(map:YamlMap):Bool
	{
		if (map.entries.length == 0) return false;
		var first = map.entries[0].value;
		if (first.isNull()) return false;
		if (isFlowValue(first)) return true;
		if (Std.isOfType(first, YamlMap))
		{
			// A non-empty block mapping is written like `- _BaseMap:` with its
			// fields one step deeper; an empty one stays on a bare dash.
			return !(cast first : YamlMap).isEmpty();
		}
		if (Std.isOfType(first, YamlSeq))
		{
			// Same for a block sequence: `- PackageNames:` with the list's dashes
			// at the key's own indent, as Unity writes configurable asset lists.
			return !(cast first : YamlSeq).isEmpty();
		}
		return Std.isOfType(first, YamlScalar);
	}

	function isFlowValue(node:YamlNode):Bool
	{
		if (Std.isOfType(node, YamlMap)) return (cast node : YamlMap).flow;
		if (Std.isOfType(node, YamlSeq)) return (cast node : YamlSeq).flow;
		return false;
	}

	/** Writes a mapping's entries on the dash line, as Unity does for components. **/
	function writeCompactItem(map:YamlMap, indent:Int, contentIndent:Int):Void
	{
		var first = map.entries[0];
		var rest = map.entries.slice(1);
		var firstKey = writeKeyText(first.key);
		var prefix = firstKey + ": ";
		var value = first.value;
		if (Std.isOfType(value, YamlMap) && !(cast value : YamlMap).flow && !(cast value : YamlMap).isEmpty())
		{
			// `- _BaseMap:` with the mapping's own fields on the lines below, one
			// step deeper than the key — how Unity writes every m_TexEnvs entry.
			line(indent, "- " + firstKey + ":");
			writeBlockMap(cast value, contentIndent + indentStep);
			writeRest(rest, contentIndent);
			return;
		}
		if (Std.isOfType(value, YamlSeq) && !(cast value : YamlSeq).flow && !(cast value : YamlSeq).isEmpty())
		{
			// `- PackageNames:` with the sequence's dashes where the source had them.
			line(indent, "- " + firstKey + ":");
			writeBlockSeq(cast value, seqIndent(cast value, contentIndent));
			writeRest(rest, contentIndent);
			return;
		}
		var text = inlineValueAt(value, contentIndent + prefix.length + 1, continuationIndent(contentIndent));
		var hasMore = rest.length > 0;
		if (hasMore)
		{
			// `- target: {fileID: ...}` continues with the entry's own fields on
			// following lines, indented past the dash.
			line(indent, "- " + prefix + text);
			writeRest(rest, contentIndent);
			return;
		}
		line(indent, "- " + prefix + text);
	}

	/** Writes a compact item's remaining entries at the item's content indent. **/
	function writeRest(rest:Array<YamlEntry>, contentIndent:Int):Void
	{
		for (entry in rest)
		{
			writeMapEntry(contentIndent, entry);
		}
	}

	/** One-line rendering with a known column, used for compact sequence items. **/
	function inlineValueAt(node:YamlNode, column:Int, contIndent:Int):String
	{
		if (Std.isOfType(node, YamlMap))
		{
			return flowMapText(cast node, column, contIndent);
		}
		if (Std.isOfType(node, YamlSeq))
		{
			return flowSeqText(cast node, column, contIndent);
		}
		return scalarText(cast node);
	}

	/**
		Indent for a block sequence's dashes. Unity writes `m_Component` dashes at
		the owning key's indent but config assets indent them one step deeper, so
		the sequence remembers the column its first dash had; programmatic
		sequences fall back to [fallback].
	**/
	function seqIndent(seq:YamlSeq, fallback:Int):Int
	{
		return seq.column >= 0 ? seq.column : fallback;
	}

	/** Writes a single mapping entry, for reuse by compact sequence items. **/
	function writeMapEntry(indent:Int, entry:YamlEntry):Void
	{
		var key = writeKeyText(entry.key);
		var value = entry.value;
		if (Std.isOfType(value, YamlMap))
		{
			var child:YamlMap = cast value;
			if (child.flow)
			{
				writeFlowMapAt(indent, key, child);
			}
			else if (child.isEmpty())
			{
				line(indent, key + ":");
			}
			else
			{
				line(indent, key + ":");
				writeBlockMap(child, indent + indentStep);
			}
			return;
		}
		if (Std.isOfType(value, YamlSeq))
		{
			var child:YamlSeq = cast value;
			if (child.flow)
			{
				writeFlowSeqAt(indent, key, child);
			}
			else if (child.isEmpty())
			{
				line(indent, key + ": []");
			}
			else
			{
				line(indent, key + ":");
				writeBlockSeq(child, seqIndent(child, indent));
			}
			return;
		}
		writeScalarEntry(indent, key, cast value);
	}

	/**
		Key text with the quoting a bare write would need.

		Unity quotes the empty-string key of every plugin importer's
		`platformData` block as `''`; ordinary Unity keys are bare identifiers.
	**/
	function writeKeyText(key:String):String
	{
		if (key.length == 0) return "''";
		if (key.indexOf(": ") >= 0 || key.indexOf("\n") >= 0 || key.indexOf(" #") >= 0 || key.charAt(0) == " "
			|| key.charAt(key.length - 1) == " " || key.charAt(0) == "'" || key.charAt(0) == "\"")
		{
			return "'" + StringTools.replace(key, "'", "''") + "'";
		}
		return key;
	}

	/** Writes `key: <scalar>`, keeping multi line block scalars on their own lines. **/
	function writeScalarEntry(indent:Int, key:String, scalar:YamlScalar):Void
	{
		if (scalar.kind == Literal || scalar.kind == Folded)
		{
			var marker = (scalar.kind == Literal ? "|" : ">");
			line(indent, key + ": " + marker);
			appendText(scalar.raw, indent);
			return;
		}
		var text = scalarText(scalar);
		// An empty value keeps the source's spacing: Unity writes `value: ` with
		// a trailing space in scenes but `userData:` without one in meta files.
		var separator = scalar.raw.length == 0 && scalar.kind == Plain && !scalar.spaceAfterColon ? ":" : ": ";
		if (scalar.verbatim == null && (scalar.kind == SingleQuoted || scalar.kind == DoubleQuoted) && text.length > 0)
		{
			// Unity wraps a long quoted scalar across lines and relies on YAML
			// folding to put a space back where it broke. The continuation indent
			// follows the same max(4, key column + 2) rule its flow mappings use.
			// A parsed scalar replays its original spelling instead of re-wrapping.
			line(indent, key + ": " + wrapQuoted(text, indent, indent + key.length + 2));
			return;
		}
		line(indent, key + separator + text);
	}

	/**
		Wraps an already quoted scalar so no line exceeds [flowLineWidth].

		Breaks are only placed at a space, because YAML folding turns one line
		break into exactly one space; breaking anywhere else would change the
		value. A word longer than the budget is left alone rather than corrupted.
	**/
	function wrapQuoted(quoted:String, indent:Int, firstColumn:Int):String
	{
		if (flowLineWidth <= 0 || firstColumn + quoted.length <= flowLineWidth) return quoted;
		var prefix = Strings.spaces(continuationIndent(indent));
		var sb = new StringBuf();
		var column = firstColumn;
		var lineStart = 0;
		var i = 0;
		var length = quoted.length;
		while (i < length)
		{
			var space = quoted.indexOf(" ", i);
			if (space < 0) break;
			var nextEnd = space + 1;
			if (column + (nextEnd - lineStart) > flowLineWidth && space > lineStart)
			{
				sb.add(quoted.substring(lineStart, space));
				sb.add("\n");
				sb.add(prefix);
				lineStart = space + 1;
				column = prefix.length;
			}
			i = nextEnd;
		}
		sb.add(quoted.substring(lineStart));
		return sb.toString();
	}

	/**
		Continuation indent Unity uses inside a wrapped value: `max(4, base + 2)`.

		[base] is the column the owning key starts at, so a key at indent 2 wraps
		its continuation to 4 and a `- target:` at dash indent 4 (key at 6) wraps
		to 8 — the two shapes Unity emits for every prefab reference.
	**/
	function continuationIndent(base:Int):Int
	{
		var continuation = base + 2;
		return continuation < 4 ? 4 : continuation;
	}

	// --------------------------------------------------------------- flow style

	function writeFlowMap(map:YamlMap, indent:Int):Void
	{
		// A flow map is rendered by the same code path a nested one uses, so a
		// short map stays on one line and a long one wraps exactly like Unity's.
		line(indent, flowMapText(map, indent + 1, continuationIndent(indent)));
	}

	/** Writes a flow mapping, with `key: ` in front when [key] is not null. **/
	function writeFlowMapAt(indent:Int, key:String, map:YamlMap):Void
	{
		var prefix = key == null ? "" : key + ": ";
		var text = flowMapText(map, indent + prefix.length + 1, continuationIndent(indent));
		line(indent, prefix + text);
	}

	function writeFlowSeqAt(indent:Int, key:String, seq:YamlSeq):Void
	{
		var prefix = key == null ? "" : key + ": ";
		var text = flowSeqText(seq, indent + prefix.length + 1, continuationIndent(indent));
		line(indent, prefix + text);
	}

	function writeFlowSeq(seq:YamlSeq, indent:Int):Void
	{
		line(indent, flowSeqText(seq, indent + 1, continuationIndent(indent)));
	}

	/**
		Renders a flow mapping, wrapping exactly where Unity wraps.

		[contentColumn] is the 1-based column the opening brace sits at and
		[contIndent] the continuation indent. Unity decides the break points by
		writing entries one by one and starting a new line after any comma that
		lands past column [flowWrapColumn] — which is why a `{fileID, guid, type}`
		reference at column 32 wraps with a 100 character first line while the
		same text at column 15 wraps at 81, and why an 89 character reference
		stays on one line. [contentColumn] below 0 disables wrapping, which is
		what nested values use because Unity only breaks at a flow collection's
		own top level commas.
	**/
	function flowMapText(map:YamlMap, contentColumn:Int, contIndent:Int):String
	{
		if (map.isEmpty()) return "{}";
		var parts = [];
		for (entry in map.entries)
		{
			parts.push(writeKeyText(entry.key) + ": " + inlineValue(entry.value));
		}
		return packFlow("{", parts, "}", contentColumn, contIndent);
	}

	/** Renders a flow sequence, wrapping the same way a flow mapping does. **/
	function flowSeqText(seq:YamlSeq, contentColumn:Int, contIndent:Int):String
	{
		if (seq.isEmpty()) return "[]";
		var parts = [];
		for (item in seq.items)
		{
			parts.push(inlineValue(item));
		}
		return packFlow("[", parts, "]", contentColumn, contIndent);
	}

	function packFlow(open:String, parts:Array<String>, close:String, contentColumn:Int, contIndent:Int):String
	{
		if (parts.length == 0) return open + close;
		if (flowWrapColumn <= 0 || contentColumn < 0) return open + parts.join(", ") + close;

		var prefix = Strings.spaces(contIndent);
		var sb = new StringBuf();
		var col = contentColumn; // column of the last character written
		var pendingBreak = false;
		sb.add(open);
		for (i in 0...parts.length)
		{
			if (i > 0)
			{
				if (pendingBreak)
				{
					sb.add("\n");
					sb.add(prefix);
					col = contIndent;
					pendingBreak = false;
				}
				else
				{
					sb.add(" ");
					col++;
				}
			}
			sb.add(parts[i]);
			col += parts[i].length;
			if (i < parts.length - 1)
			{
				sb.add(",");
				col++;
				if (col > flowWrapColumn) pendingBreak = true;
			}
		}
		sb.add(close);
		return sb.toString();
	}

	/** One-line rendering of a node for use inside a flow collection. **/
	function inlineValue(node:YamlNode):String
	{
		if (node == null) return "";
		if (Std.isOfType(node, YamlMap))
		{
			return flowMapText(cast node, -1, 0);
		}
		if (Std.isOfType(node, YamlSeq))
		{
			return flowSeqText(cast node, -1, 0);
		}
		if (!Std.isOfType(node, YamlScalar))
		{
			throw new YamlError("cannot render " + Type.getClassName(Type.getClass(node)) + " '" + node.typeName()
				+ "' inside a flow collection", node.line, node.column);
		}
		// Flow content must stay on one line, so the verbatim spelling of a
		// wrapped quoted scalar is not replayed here.
		return scalarText(cast node, false);
	}

	// ------------------------------------------------------------------ scalars

	/**
		Scalar text as it must appear in the output, quotes included.

		A quoted scalar parsed from a file replays its original spelling, so the
		escape case of `"\u7269\u4EF6"` and the fold breaks of a wrapped
		`_serializedGraph` survive unchanged. [allowVerbatim] is false inside
		flow collections, which must stay on one line.
	**/
	function scalarText(scalar:YamlScalar, allowVerbatim:Bool = true):String
	{
		var body = switch (scalar.kind)
		{
			case SingleQuoted:
				allowVerbatim && scalar.verbatim != null ? "'" + scalar.verbatim + "'" : "'" + StringTools.replace(scalar.raw, "'", "''") + "'";
			case DoubleQuoted:
				allowVerbatim && scalar.verbatim != null ? "\"" + scalar.verbatim + "\"" : quoteDouble(scalar.raw);
			case Literal | Folded:
				scalar.raw;
			case Plain:
				allowVerbatim && scalar.verbatim != null ? scalar.verbatim : plainText(scalar.raw);
		}
		if (scalar.tag != null && scalar.tag.length > 0)
		{
			return scalar.tag + " " + body;
		}
		return body;
	}

	/**
		Plain scalar text: the raw value verbatim.

		A plain scalar that was parsed from a file was plain there, so writing it
		back bare is what keeps `folderAsset: yes` byte identical instead of
		re-quoting it as `'yes'`. Programmatic values that must be quoted get a
		quoted kind from [Scalars.ofString]; [YamlScalar] nodes built by hand are
		responsible for their own kind.
	**/
	function plainText(raw:String):String
	{
		return raw;
	}

	/** Double quoted escaping, including the control characters Unity avoids. **/
	static function quoteDouble(raw:String):String
	{
		var sb = new StringBuf();
		sb.add("\"");
		for (i in 0...raw.length)
		{
			var c = raw.charCodeAt(i);
			switch (c)
			{
				case 0:
					sb.add("\\0");
				case 7:
					sb.add("\\a");
				case 8:
					sb.add("\\b");
				case 9:
					sb.add("\\t");
				case 10:
					sb.add("\\n");
				case 11:
					sb.add("\\v");
				case 12:
					sb.add("\\f");
				case 13:
					sb.add("\\r");
				case 27:
					sb.add("\\e");
				case 34:
					sb.add("\\\"");
				case 92:
					sb.add("\\\\");
				default:
					if (c < 0x20)
					{
						sb.add("\\x" + StringTools.hex(c, 2));
					}
					else if (c >= 0x7F)
					{
						// Unity escapes every non-ASCII character, so a parsed
						// `"\u7269\u4EF6"` writes back as the same escape text
						// instead of turning into raw UTF-8 bytes.
						sb.add("\\u" + StringTools.hex(c, 4).toLowerCase());
					}
					else
					{
						sb.addChar(c);
					}
			}
		}
		sb.add("\"");
		return sb.toString();
	}

	// -------------------------------------------------------------------- lines

	inline function line(indent:Int, text:String):Void
	{
		if (buffer.length > 0) buffer.add(lineEnding);
		var spaces = Strings.spaces(indent);
		buffer.add(spaces);
		buffer.add(text);
	}

	/**
		Appends a multi line value, indenting continuation lines by [indent].

		Used for block scalars and for folded quoted scalars, whose stored text
		already contains the line breaks.
	**/
	function appendText(text:String, indent:Int):Void
	{
		var lines = Strings.splitLines(text);
		for (l in lines)
		{
			line(indent, l);
		}
	}

	/** Escapes [text] for inclusion in a JSON string. **/
	public static function writeJsonString(sb:StringBuf, text:String):Void
	{
		sb.add("\"");
		for (i in 0...text.length)
		{
			var c = text.charCodeAt(i);
			switch (c)
			{
				case 34:
					sb.add("\\\"");
				case 92:
					sb.add("\\\\");
				case 10:
					sb.add("\\n");
				case 13:
					sb.add("\\r");
				case 9:
					sb.add("\\t");
				default:
					if (c < 0x20)
					{
						sb.add("\\u" + StringTools.hex(c, 4));
					}
					else
					{
						sb.addChar(c);
					}
			}
		}
		sb.add("\"");
	}
}
