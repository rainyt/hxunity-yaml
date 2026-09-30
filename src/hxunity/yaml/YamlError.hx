package hxunity.yaml;

/**
	Parse/serialise error raised by [hxunity.yaml] with a source position.

	Unity YAML is machine generated, so a syntax error almost always means the
	file was hand edited and corrupted. The position information is therefore
	kept precise enough to point at the offending line.
**/
class YamlError
{
	/** Human readable description of the problem. **/
	public var message(default, null):String;

	/** 1 based line number the error was detected on, or 0 when unknown. **/
	public var line(default, null):Int;

	/** 0 based column the error was detected on, or -1 when unknown. **/
	public var column(default, null):Int;

	public function new(message:String, line:Int = 0, column:Int = -1)
	{
		this.message = message;
		this.line = line;
		this.column = column;
	}

	/** Formats the error including its source position. **/
	public function toString():String
	{
		if (line <= 0) return 'YamlError: $message';
		if (column < 0) return 'YamlError: $message (line $line)';
		return 'YamlError: $message (line $line, column ${column + 1})';
	}
}
