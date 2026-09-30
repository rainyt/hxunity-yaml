package hxunity.yaml;

import haxe.Int64;

/** One token, with the source position needed to re-emit or report it. **/
class YamlToken
{
	public var type:YamlTokenType;

	/** 1 based source line. **/
	public var line:Int;

	/** 0 based column of the token itself. **/
	public var column:Int;

	/** Indentation of the line the token started on, in spaces. **/
	public var indent:Int;

	/** Scalar text, key name, or the raw `---` header text. **/
	public var text:String;

	/** How [text] was quoted, for [Scalar] tokens. **/
	public var kind:ScalarKind;

	/** Explicit tag written before a scalar, e.g. `!u!114`, or `null`. **/
	public var tag:String;

	/** Anchor declared after a scalar, or `null`. **/
	public var anchor:String;

	/** Alias referenced as the value, e.g. `*root`, or `null`. **/
	public var alias:String;

	/** Class id parsed out of a [DocStart] header. **/
	public var classId:Int;

	/** Anchor parsed out of a [DocStart] header. **/
	public var fileId:haxe.Int64;

	/** True when a [DocStart] header ended with `stripped`. **/
	public var stripped:Bool;

	public function new(type:YamlTokenType, line:Int, column:Int, indent:Int)
	{
		this.type = type;
		this.line = line;
		this.column = column;
		this.indent = indent;
		this.text = "";
		this.kind = Plain;
		this.tag = null;
		this.anchor = null;
		this.alias = null;
		this.classId = 0;
		this.fileId = haxe.Int64.ofInt(0);
		this.stripped = false;
	}

	/** True when this token is a scalar carrying a value. **/
	public function hasText():Bool
	{
		return text != null && text.length > 0;
	}

	public function toString():String
	{
		return switch (type)
		{
			case DocStart: '--- !u!$classId &${haxe.Int64.toStr(fileId)}${stripped ? " stripped" : ""}';
			case BareDocStart: "---";
			case DocEnd: "...";
			case Directive: text;
			case Key: '$text:';
			case Dash: "-";
			case FlowSeqStart: "[";
			case FlowSeqEnd: "]";
			case FlowMapStart: "{";
			case FlowMapEnd: "}";
			case Comma: ",";
			case Scalar: text;
			case Eof: "<eof>";
		}
	}
}
