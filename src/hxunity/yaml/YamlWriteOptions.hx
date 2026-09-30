package hxunity.yaml;

/** Options controlling [YamlWriter]. **/
typedef YamlWriteOptions = {
	/** Spaces per block indent level. Unity uses 2. **/
	@:optional var indentStep:Int;

	/**
		Column budget for a flow mapping written on one line. Unity wraps
		`{fileID: ..., guid: ..., type: 3}` so the comma separated entries stay
		inside 100 columns; set to 0 to disable wrapping.
	**/
	@:optional var flowLineWidth:Int;

	/** Line ending to join emitted lines with. Defaults to `\n`. **/
	@:optional var lineEnding:String;

	/** Appends a line ending after the last line. Defaults to true. **/
	@:optional var trailingNewline:Bool;
}
