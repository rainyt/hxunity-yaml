package hxunity.prefab;

import hxunity.yaml.ScalarKind;
import hxunity.yaml.Scalars;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.YamlSeq;

/**
	Unity 的 `propertyPath`（PrefabInstance 覆盖里定位属性的路径）。

	形如 `m_Name`、`m_LocalPosition.x`、
	`AnimateDatas.Array.data[1].ChildTargetDatas.Array.data[5].Target`：
	字段名与 `Array.data[N]` 下标用 `.` 连接，`Array.data[N]` 对应 YAML 数组
	（块式 `- ` 序列）的第 N 项。路径最终都落在 [YamlMap] / [YamlSeq] 上，
	本类只负责按 Unity 的记法走这棵树。
**/
/**
	路径的一段：字段名或数组下标。
**/
enum PropertySegment
{
	Field(name:String);
	Index(index:Int);
}

class PropertyPath
{
	/** 把 Unity 记法的路径解析成段序列。空路径返回空数组。 **/
	public static function parse(path:String):Array<PropertySegment>
	{
		var segments:Array<PropertySegment> = [];
		if (path == null || path.length == 0) return segments;
		var tokens = path.split(".");
		var i = 0;
		while (i < tokens.length)
		{
			var token = tokens[i];
			if (token == "Array" && i + 1 < tokens.length && StringTools.startsWith(tokens[i + 1], "data["))
			{
				segments.push(Index(indexOf(tokens[i + 1])));
				i += 2;
				continue;
			}
			if (StringTools.startsWith(token, "data["))
			{
				segments.push(Index(indexOf(token)));
				i++;
				continue;
			}
			segments.push(Field(token));
			i++;
		}
		return segments;
	}

	static function indexOf(token:String):Int
	{
		var open = token.indexOf("[");
		var close = token.lastIndexOf("]");
		if (open < 0 || close <= open) return 0;
		var value = Std.parseInt(token.substring(open + 1, close));
		return value == null ? 0 : value;
	}

	/** 读取路径终点的节点；任何一段不存在返回 `null`。 **/
	public static function get(root:YamlNode, path:String):YamlNode
	{
		var segments = parse(path);
		if (segments.length == 0) return null;
		var node = root;
		for (i in 0...segments.length - 1)
		{
			node = step(node, segments[i], false);
			if (node == null) return null;
		}
		return step(node, segments[segments.length - 1], false);
	}

	/**
		把 [value] 写到路径终点，返回是否写入。

		缺失的中间字段自动创建空映射；数组下标越界时以空标量扩容，对应 Unity
		反序列化器"按需增长数组"的行为。路径穿过标量这类不可能的结构时返回
		`false` 而不是抛异常，调用方按条目计数即可。
	**/
	public static function set(root:YamlNode, path:String, value:YamlNode):Bool
	{
		var segments = parse(path);
		if (segments.length == 0) return false;
		var node = root;
		for (i in 0...segments.length - 1)
		{
			node = step(node, segments[i], true);
			if (node == null) return false;
		}
		var last:PropertySegment = segments[segments.length - 1];
		switch (last)
		{
			case Field(name):
				var map = mapOf(node);
				if (map == null) return false;
				map.set(name, value);
				return true;
			case Index(index):
				var seq = seqOf(node);
				if (seq == null) return false;
				while (seq.length() <= index)
				{
					seq.push(new YamlScalar("", Plain));
				}
				seq.items[index] = value;
				return true;
		}
	}

	static function step(node:YamlNode, segment:PropertySegment, create:Bool):YamlNode
	{
		switch (segment)
		{
			case Field(name):
				var map = mapOf(node);
				if (map == null) return null;
				var next = map.get(name);
				if (next == null && create)
				{
					next = new YamlMap();
					map.set(name, next);
				}
				return next;
			case Index(index):
				var seq = seqOf(node);
				if (seq == null) return null;
				if (index >= seq.length())
				{
					if (!create) return null;
					while (seq.length() <= index)
					{
						seq.push(new YamlScalar("", Plain));
					}
				}
				return seq.get(index);
		}
	}

	static function mapOf(node:YamlNode):YamlMap
	{
		return node != null && Std.isOfType(node, YamlMap) ? cast node : null;
	}

	static function seqOf(node:YamlNode):YamlSeq
	{
		return node != null && Std.isOfType(node, YamlSeq) ? cast node : null;
	}
}
