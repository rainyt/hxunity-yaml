package hxunity.yaml;

/** Kinds of token produced by [YamlLexer]. **/
enum YamlTokenType
{
	/** A `---` document header, carrying its `!u!` class id, anchor and flags. **/
	DocStart;

	/** A `---` with no Unity tag, as a hand written fixture may use. **/
	BareDocStart;

	/** A `...` document end marker. **/
	DocEnd;

	/** A `%YAML` or `%TAG` directive line. **/
	Directive;

	/** `key:` at the start of a block mapping entry. **/
	Key;

	/** `-` starting a block sequence item. **/
	Dash;

	/** `[` opening a flow sequence. **/
	FlowSeqStart;

	/** `]` closing a flow sequence. **/
	FlowSeqEnd;

	/** `{` opening a flow mapping. **/
	FlowMapStart;

	/** `}` closing a flow mapping. **/
	FlowMapEnd;

	/** `,` separating flow collection entries. **/
	Comma;

	/** A scalar value, or a `key: value` pair written inside a flow mapping. **/
	Scalar;

	/** End of input. **/
	Eof;
}
