package hxunity.types;

import hxunity.yaml.ScalarKind;
import hxunity.yaml.Scalars;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlScalar;

/**
	A Unity `Color` or `Color32`, serialised as `{r: 1, g: 1, b: 1, a: 1}`.

	Unity writes the same shape for both types. A `Color32` stores bytes but is
	still written as normalised floats in a float field, so this class does not
	need to know which one the component declared.
**/
class ColorData
{
	public var r:Float;
	public var g:Float;
	public var b:Float;
	public var a:Float;

	public function new(r:Float = 0, g:Float = 0, b:Float = 0, a:Float = 1)
	{
		this.r = r;
		this.g = g;
		this.b = b;
		this.a = a;
	}

	/** Reads a colour from a mapping, or `null`. **/
	public static function fromNode(node:YamlNode):ColorData
	{
		if (node == null || !Std.isOfType(node, YamlMap)) return null;
		var map:YamlMap = cast node;
		return new ColorData(component(map, "r", 0), component(map, "g", 0), component(map, "b", 0), component(map, "a", 1));
	}

	/** Reads a colour from a component field, or `null`. **/
	public static function fromField(fields:YamlMap, key:String):ColorData
	{
		return fields == null ? null : fromNode(fields.get(key));
	}

	/** Reads a colour from a `#RRGGBB` / `#RRGGBBAA` hex string. **/
	public static function fromHex(hex:String):ColorData
	{
		var text = StringTools.startsWith(hex, "#") ? hex.substr(1) : hex;
		var value = Std.parseInt("0x" + text);
		if (value == null) throw 'malformed colour "$hex"';
		if (text.length <= 6)
		{
			return new ColorData(((value >> 16) & 0xFF) / 255, ((value >> 8) & 0xFF) / 255, (value & 0xFF) / 255, 1);
		}
		return new ColorData(((value >> 24) & 0xFF) / 255, ((value >> 16) & 0xFF) / 255, ((value >> 8) & 0xFF) / 255,
			(value & 0xFF) / 255);
	}

	static function component(map:YamlMap, key:String, fallback:Float):Float
	{
		var text = map.getString(key);
		if (text == null) return fallback;
		var value = Scalars.tryFloat(text);
		return value == null ? fallback : value;
	}

	/** Writes the flow mapping Unity expects, in `r, g, b, a` order. **/
	public function toNode():YamlMap
	{
		var map = new YamlMap(null, true);
		map.set("r", scalar(r));
		map.set("g", scalar(g));
		map.set("b", scalar(b));
		map.set("a", scalar(a));
		return map;
	}

	/** This colour as `#RRGGBBAA`. **/
	public function toHex():String
	{
		var sb = new StringBuf();
		sb.add("#");
		for (channel in [r, g, b, a])
		{
			var byte = Std.int(Math.max(0, Math.min(1, channel)) * 255 + 0.5);
			sb.add(StringTools.hex(byte, 2));
		}
		return sb.toString().toUpperCase();
	}

	public function toString():String
	{
		return toHex();
	}

	static function scalar(value:Float):YamlScalar
	{
		return new YamlScalar(Numbers.format(value), ScalarKind.Plain);
	}
}
