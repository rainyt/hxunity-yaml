package hxunity.yaml;

import haxe.Int64;

/**
	Recursive descent parser for the YAML 1.1 dialect Unity 2022.3 writes.

	The parser is deliberately forgiving about indentation width — it derives
	block structure from the indent values in the token stream rather than
	assuming two spaces — because a hand edited prefab may use four. What it does
	not tolerate is malformed Unity structure, such as a `---` header whose
	`!u!` class id is missing: that raises a [YamlError] with a line number.
**/
class YamlParser
{
	/** Parses a single document body, throwing [YamlError] on malformed input. **/
	public static function parse(text:String, ?options:YamlParseOptions):YamlNode
	{
		var parser = new YamlParser(text, options);
		return parser.parseDocumentBody();
	}

	/** Parses every document in [text], in file order. **/
	public static function parseAll(text:String, ?options:YamlParseOptions):Array<UnityYamlDocument>
	{
		var parser = new YamlParser(text, options);
		return parser.parseDocuments();
	}

	var lexer:YamlLexer;
	var tokens:Array<YamlToken>;
	var index:Int;
	var options:YamlParseOptions;
	var anchors:Map<String, YamlNode>;
	var aliases:Array<{node:YamlScalar, name:String}>;
	var depth:Int;

	static inline var MAX_DEPTH = 512;

	function new(text:String, ?options:YamlParseOptions)
	{
		this.lexer = new YamlLexer(text);
		this.options = options == null ? {} : options;
		this.tokens = [];
		this.index = 0;
		this.anchors = new Map();
		this.aliases = [];
		this.depth = 0;
		fill(2);
	}

	function fill(count:Int):Void
	{
		while (count > 0)
		{
			var token = lexer.next();
			if (token == null || token.type == Eof)
			{
				tokens.push(new YamlToken(Eof, lexer.line, lexer.column, 0));
				return;
			}
			tokens.push(token);
			if (token.type == Eof) return;
			count--;
		}
	}

	inline function peek(offset:Int = 0):YamlToken
	{
		var at = index + offset;
		if (at >= tokens.length) return tokens[tokens.length - 1];
		return tokens[at];
	}

	inline function advance():YamlToken
	{
		var token = peek();
		index++;
		if (index >= tokens.length - 1) fill(2);
		return token;
	}

	function fail(message:String, ?token:YamlToken):Dynamic
	{
		var t = token == null ? peek() : token;
		throw new YamlError(message, t.line, t.column);
	}

	// ---------------------------------------------------------------- documents

	/**
		Skips directives and headers and parses the body that follows.

		Returns the body of the last document, which is what a caller wants when
		reading a single `.asset` file.
	**/
	function parseDocumentBody():YamlNode
	{
		var body:YamlNode = new YamlMap();
		while (true)
		{
			var token = peek();
			switch (token.type)
			{
				case Directive, BareDocStart:
					advance();
				case DocStart, DocEnd:
					advance();
				case Eof:
					return body;
				default:
					body = parseBlockNode();
					// Leave the token that ended the body for the next document.
					while (peek().type == DocEnd)
					{
						advance();
					}
					return body;
			}
		}
		return body;
	}

	/** Parses every `--- !u!` document in the stream. **/
	public function parseDocuments():Array<UnityYamlDocument>
	{
		var out = [];
		var pendingDirectives:Array<String> = [];
		while (true)
		{
			var token = peek();
			switch (token.type)
			{
				case Directive:
					pendingDirectives.push(token.text);
					advance();
				case DocEnd:
					advance();
				case DocStart:
					var header = advance();
					var body = parseBlockNode();
					out.push(new UnityYamlDocument(header.classId, header.fileId, header.stripped, body, header.line, true, true));
					pendingDirectives = [];
					resolvePendingAliases();
				case BareDocStart:
					// `---` with no `!u!` tag: a hand written fixture, or a document
					// whose type only the body's class-name key can tell us.
					var header = advance();
					var body = parseBlockNode();
					out.push(new UnityYamlDocument(0, Int64.ofInt(0), false, body, header.line, false, true));
					pendingDirectives = [];
					resolvePendingAliases();
				case Eof:
					return out;
				default:
					// Content before the first header, for example a `.meta` file
					// that starts straight with `fileFormatVersion: 2`.
					var body = parseBlockNode();
					out.push(new UnityYamlDocument(0, Int64.ofInt(0), false, body, token.line, false, false));
					resolvePendingAliases();
			}
		}
		return out;
	}

	// ------------------------------------------------------------ block parsing

	/**
		Parses the node that starts at the current token.

		The token stream is already indentation aware, so this only has to decide
		between a mapping, a sequence and a scalar.
	**/
	function parseBlockNode():YamlNode
	{
		depth++;
		if (depth > MAX_DEPTH)
		{
			depth--;
			fail("document nesting is too deep (more than " + MAX_DEPTH + " levels)");
		}
		var node:YamlNode;
		var token = peek();
		switch (token.type)
		{
			case Key:
				node = parseMapping(token.indent);
			case Dash:
				node = parseSequence(token.indent);
			case FlowMapStart:
				node = parseFlowMap();
			case FlowSeqStart:
				node = parseFlowSeq();
			case Scalar:
				node = parseScalarToken(advance());
			case DocStart | BareDocStart | DocEnd | Eof:
				node = new YamlScalar("", Plain, token.line, token.column);
			case Directive:
				advance();
				node = parseBlockNode();
			case FlowMapEnd | FlowSeqEnd | Comma:
				fail("unexpected '" + token.toString() + "'");
				node = null;
		}
		depth--;
		return node;
	}

	/** Parses consecutive `key:` entries at exactly [indent]. **/
	function parseMapping(indent:Int):YamlMap
	{
		var map = new YamlMap(null, false, peek().line, peek().column);
		while (true)
		{
			var token = peek();
			if (token.type != Key || token.indent != indent) break;
			advance();
			var key = token.text;
			if (options.rejectDuplicateKeys && map.has(key))
			{
				fail('duplicate key "$key"', token);
			}
			var value = parseMappingValue(token);
			map.add(key, value);
		}
		return map;
	}

	/**
		Parses the value of a block mapping entry whose key token was [key].

		A value written after the `:` on the key's own line is parsed inline. A
		value on a later line must be indented deeper, or be a `- ` sequence whose
		dash sits at the key's own indent — the shape Unity uses for `m_Component`
		and `m_Children`.
	**/
	function parseMappingValue(key:YamlToken):YamlNode
	{
		var indent = key.indent;
		var token = peek();
		if (token.type == Eof || token.type == DocStart || token.type == BareDocStart || token.type == DocEnd)
		{
			return emptyAt(token);
		}
		if (token.line == key.line)
		{
			// Same line as the key, so this is the value: `m_Icon: {fileID: 0}`.
			return parseInlineValue();
		}
		if (token.type == Key && token.indent == indent)
		{
			// `key:` with nothing after it, followed by the next sibling key.
			return emptyAt(token);
		}
		if (token.indent > indent)
		{
			return parseBlockNode();
		}
		if (token.type == Dash && token.indent == indent)
		{
			return parseSequence(indent);
		}
		return emptyAt(token);
	}

	/**
		Parses a value that follows its `:` on the same line.

		Block mappings and sequences cannot start mid-line in Unity's output, so
		the shapes here are a scalar, `{...}` and `[...]`.
	**/
	function parseInlineValue():YamlNode
	{
		var token = peek();
		switch (token.type)
		{
			case FlowMapStart:
				return parseFlowMap();
			case FlowSeqStart:
				return parseFlowSeq();
			case Scalar:
				advance();
				return parseScalarToken(token);
			case Key:
				// A nested key on the same line means the line held more than one
				// entry, which Unity never writes. Treat the text as a scalar so
				// nothing is lost.
				advance();
				return new YamlScalar(token.text, token.kind, token.line, token.column, token.tag, token.anchor);
			case Dash:
				advance();
				return new YamlScalar("-", Plain, token.line, token.column);
			case Directive:
				advance();
				return emptyAt(token);
			case Eof | DocStart | BareDocStart | DocEnd | FlowMapEnd | FlowSeqEnd | Comma:
				return emptyAt(token);
		}
	}

	/** Parses consecutive `- ` items whose dash sits at exactly [indent]. **/
	function parseSequence(indent:Int):YamlSeq
	{
		var seq = new YamlSeq(null, false, peek().line, peek().column);
		while (true)
		{
			var token = peek();
			if (token.type != Dash || token.indent != indent) break;
			var content = peek(1);
			if (content.type == Eof || content.type == DocStart || content.type == BareDocStart || content.type == DocEnd)
			{
				advance();
				seq.push(emptyAt(content));
				continue;
			}
			if (content.type == Key && content.line == token.line && content.column > token.column)
			{
				// `- key: value` written on one line. Unity puts a sequence's dashes
				// at the indentation of the key that owns them, so the item's
				// remaining keys are indented past the dash — see [parseItemMapping]
				// for how those are picked up without swallowing the owning key's
				// next sibling.
				advance();
				seq.push(parseItemMapping(content.indent, token.indent, token.line));
				continue;
			}
			if (content.type == Dash && content.line == token.line)
			{
				// `- - x` nested inline sequence; rare, handled for completeness.
				advance();
				seq.push(parseBlockNode());
				continue;
			}
			if (content.line == token.line && (content.type == FlowMapStart || content.type == FlowSeqStart))
			{
				// `- {fileID: 123}` and `- []` on the dash line.
				advance();
				seq.push(parseBlockNode());
				continue;
			}
			advance();
			if (content.line == token.line)
			{
				// The value sits after the dash on the dash's own line, so it
				// belongs to this item no matter how it is indented. Unity writes
				// `- one`, `- {fileID: 1}` and `- component: {fileID: 2}` this way.
				seq.push(parseBlockNode());
			}
			else if (content.indent > indent)
			{
				// A block value on a later line, indented past the dash.
				seq.push(parseBlockNode());
			}
			else
			{
				// The next token is not indented past the dash, so the dash carries
				// no content. Unity writes exactly this for a component whose
				// reference is null.
				seq.push(emptyAt(content));
			}
		}
		return seq;
	}

	function emptyAt(token:YamlToken):YamlScalar
	{
		return new YamlScalar("", Plain, token.line, token.column);
	}

	/**
		Parses the mapping of a sequence item whose first key was written on the
		dash line, as in Unity's `m_Modifications` entries.

		[firstKeyIndent] is the indentation of that first key and [dashIndent] the
		indentation of the dash carrying it. Unity writes

		```yaml
		    - target: {fileID: 4511153011648551893, guid: 75e48dfe44cab60438c20657f7f6f739,
		        type: 3}
		      propertyPath: m_Name
		      value: banquet_0205_14
		```

		so the dash and its first key share an indent and the item's remaining keys
		sit one step further in. Only keys on [firstLine] or at the item's own
		content indent are consumed, which is what stops the next sibling of the key
		that owns the sequence from being swallowed.
	**/
	function parseItemMapping(firstKeyIndent:Int, dashIndent:Int, firstLine:Int):YamlMap
	{
		var map = new YamlMap(null, false, peek().line, peek().column);
		var contentIndent = firstKeyIndent > dashIndent ? firstKeyIndent : dashIndent + INDENT_STEP;
		while (true)
		{
			var token = peek();
			if (token.type != Key) break;
			if (token.line == firstLine)
			{
				if (token.indent != firstKeyIndent) break;
			}
			else if (token.indent != contentIndent)
			{
				break;
			}
			advance();
			map.add(token.text, parseInlineValue());
		}
		return map;
	}

	/** Indentation step assumed when locating a sequence item's remaining keys. **/
	static inline var INDENT_STEP = 2;

	// ------------------------------------------------------------- flow parsing

	/** Parses `{ ... }`, including Unity's line-wrapped form. **/
	function parseFlowMap():YamlMap
	{
		var open = advance(); // `{`
		var map = new YamlMap(null, true, open.line, open.column);
		if (peek().type == FlowMapEnd)
		{
			advance();
			return map;
		}
		while (true)
		{
			var keyToken = peek();
			if (keyToken.type == FlowMapEnd)
			{
				advance();
				break;
			}
			if (keyToken.type == Eof)
			{
				fail("unterminated flow mapping, expected '}'", keyToken);
			}
			var key = readFlowKey(keyToken);
			if (peek().type == Key)
			{
				// The lexer saw the `:` on its own, for example `{fileID : 0}`.
				advance();
			}
			var value = readFlowValue();
			map.add(key, value);
			if (peek().type == Comma)
			{
				advance();
				continue;
			}
			if (peek().type == FlowMapEnd)
			{
				advance();
				break;
			}
			if (peek().type == Eof)
			{
				fail('unterminated flow mapping: the "{" opened on line ${open.line} is never closed', open);
			}
			fail("expected ',' or '}' in a flow mapping", peek());
		}
		return map;
	}

	/** Parses `[ ... ]`, including the empty `[]` Unity writes. **/
	function parseFlowSeq():YamlSeq
	{
		var open = advance(); // `[`
		var seq = new YamlSeq(null, true, open.line, open.column);
		if (peek().type == FlowSeqEnd)
		{
			advance();
			return seq;
		}
		while (true)
		{
			if (peek().type == FlowSeqEnd)
			{
				advance();
				break;
			}
			if (peek().type == Eof)
			{
				fail('unterminated flow sequence: the "[" opened on line ${open.line} is never closed', open);
			}
			seq.push(readFlowValue());
			if (peek().type == Comma)
			{
				advance();
				continue;
			}
			if (peek().type == FlowSeqEnd)
			{
				advance();
				break;
			}
			if (peek().type == Eof)
			{
				fail('unterminated flow sequence: the "[" opened on line ${open.line} is never closed', open);
			}
			fail("expected ',' or ']' in a flow sequence", peek());
		}
		return seq;
	}

	/** Reads a flow mapping key, which the lexer emits as [Scalar] or [Key]. **/
	function readFlowKey(token:YamlToken):String
	{
		switch (token.type)
		{
			case Key | Scalar:
				advance();
				return token.text;
			case FlowMapStart:
				// Complex keys are not produced by Unity; keep reading anyway.
				return parseFlowMap().toString();
			default:
				fail("expected a key in a flow mapping", token);
				return null;
		}
	}

	/**
		Reads one value inside a flow collection.

		Handles the three shapes Unity emits: a scalar (possibly quoting a nested
		JSON blob), `[]`, and `{...}`. Newlines inside the collection are already
		gone by this point because the lexer consumed the wrapped continuation.
	**/
	function readFlowValue():YamlNode
	{
		var token = peek();
		switch (token.type)
		{
			case FlowSeqStart:
				return parseFlowSeq();
			case FlowMapStart:
				return parseFlowMap();
			case Key:
				// `{a: 1}` after the lexer saw the `:` as a Key token.
				advance();
				return new YamlScalar(token.text, token.kind, token.line, token.column, token.tag, token.anchor);
			case Scalar:
				advance();
				return parseScalarToken(token);
			case FlowSeqEnd | FlowMapEnd:
				return emptyAt(token);
			case Comma:
				// `{fileID: 0,}` and `[a, ]` trailing separators.
				advance();
				return readFlowValue();
			case Dash:
				advance();
				return new YamlScalar("-", Plain, token.line, token.column);
			case Eof:
				fail("unexpected end of input inside a flow collection", token);
				return null;
			case DocStart | BareDocStart | DocEnd | Directive:
				fail("unexpected document marker inside a flow collection", token);
				return null;
		}
	}

	// ------------------------------------------------------------------ scalars

	function parseScalarToken(token:YamlToken):YamlScalar
	{
		if (token.alias != null)
		{
			var scalar = new YamlScalar(token.alias, Plain, token.line, token.column);
			aliases.push({node: scalar, name: token.alias});
			return scalar;
		}
		var scalar = new YamlScalar(token.text, token.kind, token.line, token.column, token.tag, token.anchor);
		if (token.anchor != null)
		{
			anchors.set(token.anchor, scalar);
		}
		return scalar;
	}

	/**
		Replaces alias nodes recorded since the last document with the anchored
		node they name.

		Called at document boundaries so an alias never resolves across documents.
	**/
	function resolvePendingAliases():Void
	{
		if (aliases.length > 0 && options.resolveAliases)
		{
			for (entry in aliases)
			{
				var target = anchors.get(entry.name);
				if (target != null)
				{
					entry.node.setRaw(target.toString());
				}
			}
		}
		aliases = [];
		anchors = new Map();
	}
}
