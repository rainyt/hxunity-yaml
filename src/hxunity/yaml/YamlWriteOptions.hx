package hxunity.yaml;

/** Options controlling [YamlWriter]. **/
typedef YamlWriteOptions = {
	/** Spaces per block indent level. Unity uses 2. **/
	@:optional var indentStep:Int;

	/**
		Column budget for a wrapped quoted scalar. Unity folds long quoted strings
		(such as `_serializedGraph`) at spaces; set to 0 to disable wrapping.
	**/
	@:optional var flowLineWidth:Int;

	/**
		Column a flow collection's separator comma may reach before the entries
		wrap to a continuation line. Unity breaks past column 80, which is what
		reproduces its `{fileID: ..., guid: ..., type: 3}` wraps exactly; set to
		0 to keep every flow collection on one line.
	**/
	@:optional var flowWrapColumn:Int;

	/** Line ending to join emitted lines with. Defaults to `\n`. **/
	@:optional var lineEnding:String;

	/** Appends a line ending after the last line. Defaults to true. **/
	@:optional var trailingNewline:Bool;
}
