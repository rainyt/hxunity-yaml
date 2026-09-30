package hxunity.yaml;

/**
	A parsed YAML node: a mapping, a sequence or a scalar.

	Nodes are a closed set of three classes. Downcasting is available through
	[asMap], [asSeq] and [asScalar], which throw a positioned [YamlError] instead
	of returning `null`, so a malformed prefab fails with a usable message
	rather than a null dereference.
**/
@:allow(hxunity.yaml.YamlParser)
@:allow(hxunity.yaml.YamlWriter)
class YamlNode
{
	/** 1 based line the node started on, or 0 when unknown. **/
	public var line(default, null):Int;

	/** 0 based column the node started on, or -1 when unknown. **/
	public var column(default, null):Int;

	function new(line:Int, column:Int)
	{
		this.line = line;
		this.column = column;
	}

	/** True for [YamlMap] and [YamlSeq]. **/
	public function isCollection():Bool
	{
		return false;
	}

	/**
		This node as a map, or throws when it is not one.

		Every subclass overrides the accessor that matches it; the base class
		implementations throw so a wrong assumption fails with the source position
		rather than a null dereference somewhere else.
	**/
	public function asMap():YamlMap
	{
		throw new YamlError("expected a mapping but found " + typeName(), line, column);
	}

	/** This node as a sequence, or throws when it is not one. **/
	public function asSeq():YamlSeq
	{
		throw new YamlError("expected a sequence but found " + typeName(), line, column);
	}

	/** This node as a scalar, or throws when it is a collection. **/
	public function asScalar():YamlScalar
	{
		throw new YamlError("expected a scalar but found " + typeName(), line, column);
	}

	/** True when this node is a scalar with an empty value. **/
	public function isNull():Bool
	{
		return false;
	}

	/**
		Scalar text as written in the source.

		Collections return `""`; use [toJson] to inspect them.
	**/
	public function toString():String
	{
		return "";
	}

	/** Short name of the node kind, used in error messages. **/
	public function typeName():String
	{
		return "node";
	}

	/** Deep comparison that also checks node kinds and quoting styles. **/
	public function deepEquals(other:YamlNode):Bool
	{
		return false;
	}

	/**
		Converts the node tree into plain Haxe values: [String], [haxe.Int64],
		[Float], [Bool], [Array], [Map] and `null`. Intended for tooling and
		debugging.
	**/
	public function toHaxe():Dynamic
	{
		return null;
	}

	/** Pretty prints the node tree as JSON. Handy when debugging a prefab. **/
	public function toJson(indent:Int = 0):String
	{
		var sb = new StringBuf();
		writeJson(sb, indent);
		return sb.toString();
	}

	function writeJson(sb:StringBuf, indent:Int):Void {}
}
