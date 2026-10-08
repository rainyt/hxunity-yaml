package hxunity.yaml;

/** A YAML sequence that preserves item order. **/
class YamlSeq extends YamlNode
{
	/** Sequence items. **/
	public var items(default, null):Array<YamlNode>;

	/** True when the source wrote the sequence in flow style, `[a, b]`. **/
	public var flow(default, null):Bool;

	public function new(items:Array<YamlNode> = null, flow:Bool = false, line:Int = 0, column:Int = -1)
	{
		super(line, column);
		this.items = items == null ? [] : items;
		this.flow = flow;
	}

	override public function isCollection():Bool
	{
		return true;
	}

	override public function deepClone():YamlNode
	{
		var out = new YamlSeq(null, flow, line, column);
		for (item in items)
		{
			out.items.push(item == null ? null : item.deepClone());
		}
		return out;
	}

	override public function asSeq():YamlSeq
	{
		return this;
	}

	/** Throws: a sequence is not a mapping, and a positioned error says where. **/
	override public function asMap():YamlMap
	{
		throw new YamlError("expected a mapping but found a sequence", line, column);
	}

	/** Throws: a sequence is not a scalar, and a positioned error says where. **/
	override public function asScalar():YamlScalar
	{
		throw new YamlError("expected a scalar but found a sequence", line, column);
	}

	override public function typeName():String
	{
		return flow ? "flow sequence" : "sequence";
	}

	/** Number of items. **/
	public function length():Int
	{
		return items.length;
	}

	/** True when the sequence has no items. **/
	public function isEmpty():Bool
	{
		return items.length == 0;
	}

	/** Item at [index], or `null` when out of range. **/
	public function get(index:Int):YamlNode
	{
		return (index < 0 || index >= items.length) ? null : items[index];
	}

	/** Appends [item] and returns it. **/
	public function push(item:YamlNode):YamlNode
	{
		items.push(item);
		return item;
	}

	/** Removes the item at [index] and returns it, or `null`. **/
	public function removeAt(index:Int):YamlNode
	{
		if (index < 0 || index >= items.length) return null;
		return items.splice(index, 1)[0];
	}

	/** Removes the first item equal to [item] and returns true when it was found. **/
	public function removeItem(item:YamlNode):Bool
	{
		for (i in 0...items.length)
		{
			if (items[i] == item)
			{
				items.splice(i, 1);
				return true;
			}
		}
		return false;
	}

	/** Builds a sequence from plain values, each value goes through [Scalars.node]. **/
	public static function of(values:Array<Dynamic>):YamlSeq
	{
		var seq = new YamlSeq();
		for (value in values)
		{
			seq.push(Scalars.node(value));
		}
		return seq;
	}

	/** Reads every item as scalar text, for `m_Children` style lists. **/
	public function toStrings():Array<String>
	{
		var out = [];
		for (item in items)
		{
			out.push(item.toString());
		}
		return out;
	}

	override public function deepEquals(other:YamlNode):Bool
	{
		if (!Std.isOfType(other, YamlSeq)) return false;
		var o:YamlSeq = cast other;
		if (o.items.length != items.length) return false;
		for (i in 0...items.length)
		{
			if (!o.items[i].deepEquals(items[i])) return false;
		}
		return true;
	}

	override public function toHaxe():Dynamic
	{
		var out = [];
		for (item in items)
		{
			out.push(item.toHaxe());
		}
		return out;
	}

	override function writeJson(sb:StringBuf, indent:Int):Void
	{
		if (items.length == 0)
		{
			sb.add("[]");
			return;
		}
		var pad = Strings.spaces(indent + 2);
		sb.add("[\n");
		for (i in 0...items.length)
		{
			sb.add(pad);
			items[i].writeJson(sb, indent + 2);
			if (i < items.length - 1) sb.add(",");
			sb.add("\n");
		}
		sb.add(Strings.spaces(indent));
		sb.add("]");
	}
}
