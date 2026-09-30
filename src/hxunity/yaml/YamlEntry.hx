package hxunity.yaml;

/** One ordered key/value pair of a [YamlMap]. **/
class YamlEntry
{
	/** Field name, e.g. `m_Name`. **/
	public var key:String;

	/** Field value. **/
	public var value:YamlNode;

	/** 1 based line the key was written on. **/
	public var line:Int;

	public function new(key:String, value:YamlNode, line:Int = 0)
	{
		this.key = key;
		this.value = value;
		this.line = line;
	}

	public function toString():String
	{
		return '$key: $value';
	}
}
