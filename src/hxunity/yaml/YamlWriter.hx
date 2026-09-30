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
	* long flow mappings wrap after a comma with `max(4, indent + 4)` spaces of
	  continuation indent, and
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
	var lineEnding:String;
	var trailingNewline:Bool;

	public function new(?options:YamlWriteOptions)
	{
		this.buffer = new StringBuf();
		this.indentStep = (options == null || options.indentStep == null) ? 2 : options.indentStep;
		this.flowLineWidth = (options == null || options.flowLineWidth == null) ? 100 : options.flowLineWidth;
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
				line(indent, "- " + flowMapText(map, contentIndent));
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
				line(indent, "- " + flowSeqText(seq, contentIndent));
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
			if (text.indexOf("\n") >= 0)
			{
				line(indent, "-");
				appendText(text, contentIndent);
			}
			else
			{
				line(indent, "- " + text);
			}
		}
	}

	/**
		True when a sequence item mapping is written on the dash line.

		Unity writes `- component: {fileID: ...}`, `- _keyName: 1014000` and
		`- m_RemovedComponents: []` that way, but writes an item whose first value is
		a nested block mapping on the following line instead. Both shapes parse back
		into the same tree, so this only decides which one to emit.
	**/
	function isCompactItem(map:YamlMap):Bool
	{
		if (map.entries.length == 0) return false;
		var first = map.entries[0].value;
		if (first.isNull()) return false;
		return isFlowValue(first) || Std.isOfType(first, YamlScalar);
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
		var prefix = first.key + ": ";
		var text = inlineValueAt(first.value, contentIndent + indentStep + prefix.length);
		var hasMore = rest.length > 0;
		if (hasMore)
		{
			// `- target: {fileID: ...}` continues with the entry's own fields on
			// following lines, indented past the dash.
			line(indent, "- " + prefix + text);
			for (entry in rest)
			{
				writeMapEntry(contentIndent, entry);
			}
			return;
		}
		line(indent, "- " + prefix + text);
	}

	/** One-line rendering with a known column, used for compact sequence items. **/
	function inlineValueAt(node:YamlNode, column:Int):String
	{
		if (Std.isOfType(node, YamlMap))
		{
			return flowMapText(cast node, column);
		}
		if (Std.isOfType(node, YamlSeq))
		{
			return flowSeqText(cast node, column);
		}
		return scalarText(cast node);
	}

	/** Writes a single mapping entry, for reuse by compact sequence items. **/
	function writeMapEntry(indent:Int, entry:YamlEntry):Void
	{
		var value = entry.value;
		if (Std.isOfType(value, YamlMap))
		{
			var child:YamlMap = cast value;
			if (child.flow)
			{
				writeFlowMapAt(indent, entry.key, child);
			}
			else if (child.isEmpty())
			{
				line(indent, entry.key + ":");
			}
			else
			{
				line(indent, entry.key + ":");
				writeBlockMap(child, indent + indentStep);
			}
			return;
		}
		if (Std.isOfType(value, YamlSeq))
		{
			var child:YamlSeq = cast value;
			if (child.flow)
			{
				writeFlowSeqAt(indent, entry.key, child);
			}
			else if (child.isEmpty())
			{
				line(indent, entry.key + ": []");
			}
			else
			{
				line(indent, entry.key + ":");
				writeBlockSeq(child, indent);
			}
			return;
		}
		writeScalarEntry(indent, entry.key, cast value);
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
		if ((scalar.kind == SingleQuoted || scalar.kind == DoubleQuoted) && text.length > 0)
		{
			// Unity wraps a long quoted scalar across lines and relies on YAML
			// folding to put a space back where it broke. The continuation indent is
			// max(4, indent + 4), the same rule its flow mappings use.
			line(indent, key + ": " + wrapQuoted(text, indent, indent + key.length + 2));
			return;
		}
		line(indent, key + ": " + text);
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
		var prefix = Strings.spaces(quotedIndent(indent));
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

	/** Continuation indent Unity uses inside a wrapped value: `max(4, base + 4)`. **/
	function quotedIndent(base:Int):Int
	{
		var continuation = base + 4;
		return continuation < 4 ? 4 : continuation;
	}

	// --------------------------------------------------------------- flow style

	function writeFlowMap(map:YamlMap, indent:Int):Void
	{
		// A flow map is rendered by the same code path a nested one uses, so a
		// short map stays on one line and a long one wraps exactly like Unity's.
		line(indent, flowMapText(map, indent));
	}

	/** Writes a flow mapping, with `key: ` in front when [key] is not null. **/
	function writeFlowMapAt(indent:Int, key:String, map:YamlMap):Void
	{
		var prefix = key == null ? "" : key + ": ";
		var text = flowMapText(map, indent + prefix.length);
		line(indent, prefix + text);
	}

	function writeFlowSeqAt(indent:Int, key:String, seq:YamlSeq):Void
	{
		var prefix = key == null ? "" : key + ": ";
		var text = flowSeqText(seq, indent + prefix.length);
		line(indent, prefix + text);
	}

	function writeFlowSeq(seq:YamlSeq, indent:Int):Void
	{
		line(indent, flowSeqText(seq, indent));
	}

	/**
		Renders a flow mapping, wrapping exactly where Unity wraps.

		Entries are packed greedily while the line stays inside [flowLineWidth]
		columns; a wrapped entry starts on a continuation line indented by
		`max(4, indent + 4)`. The closing `}` is appended to the last line, so a
		wrapped mapping can end up one or two columns past the budget — which is
		exactly what Unity's own output does.
	**/
	function flowMapText(map:YamlMap, indent:Int):String
	{
		if (map.isEmpty()) return "{}";
		var parts = [];
		for (entry in map.entries)
		{
			parts.push(entry.key + ": " + inlineValue(entry.value));
		}
		return packFlow("{", parts, "}", indent);
	}

	/** Renders a flow sequence, wrapping the same way a flow mapping does. **/
	function flowSeqText(seq:YamlSeq, indent:Int):String
	{
		if (seq.isEmpty()) return "[]";
		var parts = [];
		for (item in seq.items)
		{
			parts.push(inlineValue(item));
		}
		return packFlow("[", parts, "]", indent);
	}

	function packFlow(open:String, parts:Array<String>, close:String, indent:Int):String
	{
		var total = open.length + close.length;
		for (part in parts)
		{
			total += part.length + 2; // ", " separator
		}
		if (flowLineWidth <= 0 || indent + total <= flowLineWidth)
		{
			return open + parts.join(", ") + close;
		}

		var continuation = indent + 4;
		if (continuation < 4) continuation = 4;
		var prefix = Strings.spaces(continuation);
		var lines = [];
		var current = open;
		var first = true;
		var i = 0;
		while (i < parts.length)
		{
			var piece = (first ? "" : ", ") + parts[i];
			if (first || current.length + piece.length <= flowLineWidth)
			{
				current += piece;
				first = false;
				i++;
				continue;
			}
			lines.push(current);
			current = prefix + parts[i];
			i++;
		}
		lines.push(current + close);
		return lines.join("\n" + prefix);
	}

	/** One-line rendering of a node for use inside a flow collection. **/
	function inlineValue(node:YamlNode):String
	{
		if (node == null) return "";
		if (Std.isOfType(node, YamlMap))
		{
			return flowMapText(cast node, 0);
		}
		if (Std.isOfType(node, YamlSeq))
		{
			return flowSeqText(cast node, 0);
		}
		if (!Std.isOfType(node, YamlScalar))
		{
			throw new YamlError("cannot render " + Type.getClassName(Type.getClass(node)) + " '" + node.typeName()
				+ "' inside a flow collection", node.line, node.column);
		}
		return scalarText(cast node);
	}

	// ------------------------------------------------------------------ scalars

	/** Scalar text as it must appear in the output, quotes included. **/
	function scalarText(scalar:YamlScalar):String
	{
		var body = switch (scalar.kind)
		{
			case SingleQuoted:
				"'" + StringTools.replace(scalar.raw, "'", "''") + "'";
			case DoubleQuoted:
				quoteDouble(scalar.raw);
			case Literal | Folded:
				scalar.raw;
			case Plain:
				plainText(scalar.raw);
		}
		if (scalar.tag != null && scalar.tag.length > 0)
		{
			return scalar.tag + " " + body;
		}
		return body;
	}

	/**
		Plain scalar text, quoting only when the text would not read back.

		A value such as `10f`, a guid, or `idle_01` stays bare; a value with a
		leading dash and no number, a `: ` sequence, or an empty string is quoted.
	**/
	function plainText(raw:String):String
	{
		if (raw.length == 0) return "";
		if (Scalars.needsQuoting(raw))
		{
			return "'" + StringTools.replace(raw, "'", "''") + "'";
		}
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
