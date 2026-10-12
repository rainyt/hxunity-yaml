package hxunity.unity;

import haxe.Int64;
import hxunity.prefab.UnityObject;
import hxunity.types.ColorData;
import hxunity.types.Numbers;
import hxunity.types.VectorData;
import hxunity.yaml.ScalarKind;
import hxunity.yaml.Scalars;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.YamlSeq;

/**
	Read and write access to a material's `m_SavedProperties`.

	The properties block is a set of four parallel lists, one per value type:

	```yaml
	  m_SavedProperties:
	    serializedVersion: 3
	    m_TexEnvs:
	    - _MainTex:
	        m_Texture: {fileID: 2800000, guid: 9c82410a1332d86488bd33ba37ed63f9, type: 3}
	        m_Scale: {x: 1, y: 1}
	        m_Offset: {x: 0, y: 0}
	    m_Ints: []
	    m_Floats:
	    - _Cutoff: 0.5
	    m_Colors:
	    - _Color: {r: 1, g: 1, b: 1, a: 1}
	```

	Each entry is a one key mapping whose key is the shader property name, which
	is why a lookup is a linear scan over the list — small, and the shape has to
	be preserved exactly.

	## Two details Unity cares about

	* **entries are sorted by property name** in the files Unity writes
	  (`_BaseMap` before `_Color` before `unity_Lightmaps`), so a new property is
	  inserted in that position rather than appended. A file whose lists are in a
	  different order is one Unity rewrites when it next imports the asset.
	* **a colour property is `{r, g, b, a}` even when the shader declares a
	  `Vector2`**, which is how a `_Pivot` custom property ends up as
	  `{r: 0.5, g: 0.5}` in `m_Colors`. [setVector] writes only the components the
	  vector actually has, so a two component vector comes out two components
	  wide; [setColor] always writes all four.
**/
class MaterialProperties
{
	/** The material object whose `m_SavedProperties` this reads and writes. **/
	public var object(default, null):UnityObject;

	public function new(object:UnityObject)
	{
		this.object = object;
	}

	/** Properties of [object], or `null` when it is not a material. **/
	public static function of(object:UnityObject):MaterialProperties
	{
		if (object == null) return null;
		if (!object.hasField("m_SavedProperties")) return null;
		return new MaterialProperties(object);
	}

	/**
		Properties of a material, creating an empty `m_SavedProperties` when the
		object has none.
	**/
	public static function ensure(object:UnityObject):MaterialProperties
	{
		if (object == null) return null;
		if (object.getMap("m_SavedProperties") == null)
		{
			var properties = new YamlMap();
			properties.set("serializedVersion", number(3));
			properties.set("m_TexEnvs", new YamlSeq());
			properties.set("m_Ints", new YamlSeq());
			properties.set("m_Floats", new YamlSeq());
			properties.set("m_Colors", new YamlSeq());
			object.set("m_SavedProperties", properties);
		}
		return new MaterialProperties(object);
	}

	/** The `m_SavedProperties` mapping itself. **/
	public function fields():YamlMap
	{
		return object.getMap("m_SavedProperties");
	}

	// -------------------------------------------------------------------- names

	/** Every property name in `m_TexEnvs`. **/
	public function textureProperties():Array<String>
	{
		return namesIn("m_TexEnvs");
	}

	/** Every property name in `m_Colors`. **/
	public function colorProperties():Array<String>
	{
		return namesIn("m_Colors");
	}

	/** Every property name in `m_Floats`. **/
	public function floatProperties():Array<String>
	{
		return namesIn("m_Floats");
	}

	/** Every property name in `m_Ints`. **/
	public function intProperties():Array<String>
	{
		return namesIn("m_Ints");
	}

	/** True when [property] is set in any of the four lists. **/
	public function has(property:String):Bool
	{
		return itemOf("m_TexEnvs", property) != null || itemOf("m_Ints", property) != null || itemOf("m_Floats", property) != null
			|| itemOf("m_Colors", property) != null;
	}

	// ------------------------------------------------------------------ textures

	/**
		The GUID of the texture assigned to [property], or `null`.

		A property pointing at a built-in texture, at the all zero GUID, or at
		nothing at all reports `null`: none of the three names a file on disk, and
		a caller looking for one would have to check all three anyway.
	**/
	public function getTexture(property:String):String
	{
		var reference = getTextureReference(property);
		if (reference == null || !reference.isExternal()) return null;
		if (AssetGuid.isNone(reference.guid) || AssetGuid.isBuiltin(reference.guid)) return null;
		return reference.guid;
	}

	/** The raw reference of [property], or `null` when it has no texture. **/
	public function getTextureReference(property:String):UnityReference
	{
		var env = textureEnv(property);
		return env == null ? null : UnityReference.fromNode(env.get("m_Texture"));
	}

	/** The `{m_Texture, m_Scale, m_Offset}` mapping of [property], or `null`. **/
	function textureEnv(property:String):YamlMap
	{
		var item = itemOf("m_TexEnvs", property);
		if (item == null) return null;
		var value = item.get(property);
		return (value != null && Std.isOfType(value, YamlMap)) ? cast value : null;
	}

	/**
		Assigns [guid] to [property].

		`m_Scale` and `m_Offset` are written with the defaults Unity uses when the
		entry is created, because a texture entry without them is not a shape
		Unity writes. An entry that already exists keeps its own tiling unless
		[scale] or [offset] says otherwise.
	**/
	public function setTexture(property:String, guid:String, ?fileId:Int64, ?type:Int, ?scale:VectorData, ?offset:VectorData):Void
	{
		var id = fileId == null ? AssetReference.mainObjectIdOf("png") : fileId;
		var kind = type == null ? UnityReference.TYPE_IMPORTED : type;
		var reference = new UnityReference(id, AssetGuid.normalise(guid), kind);

		var existing = textureEnv(property);
		if (existing != null)
		{
			existing.set("m_Texture", reference.toNode());
			if (scale != null) existing.set("m_Scale", scale.toNode());
			if (offset != null) existing.set("m_Offset", offset.toNode());
			return;
		}

		var map = new YamlMap();
		map.set("m_Texture", reference.toNode());
		map.set("m_Scale", (scale == null ? new VectorData(1, 1) : scale).toNode());
		map.set("m_Offset", (offset == null ? new VectorData(0, 0) : offset).toNode());
		var item = new YamlMap();
		item.set(property, map);
		insert("m_TexEnvs", property, item);
	}

	/** Clears the texture assigned to [property], keeping the property itself. **/
	public function clearTexture(property:String):Void
	{
		var env = textureEnv(property);
		if (env != null) env.set("m_Texture", UnityReference.none().toNode());
	}

	// -------------------------------------------------------------- value types

	/** The colour of [property], or `null`. **/
	public function getColor(property:String):ColorData
	{
		var item = itemOf("m_Colors", property);
		return item == null ? null : ColorData.fromNode(item.get(property));
	}

	/** Stores a colour, written as `{r: .., g: .., b: .., a: ..}`. **/
	public function setColor(property:String, value:ColorData):Void
	{
		putIn("m_Colors", property, value == null ? null : value.toNode());
	}

	/**
		The vector of [property], read from its `r` / `g` / `b` / `a` components.

		`z` and `w` come back only when the entry has `b` and `a`: a `Vector2`
		property is written two components wide and reading it as a four component
		vector would invent two.
	**/
	public function getVector(property:String):VectorData
	{
		var map = colorMap(property);
		if (map == null) return null;
		// The constructor records which of z and w were present, which is what
		// makes a Vector2 read back as a Vector2.
		var b = map.get("b");
		var a = map.get("a");
		return new VectorData(component(map, "r"), component(map, "g"), b == null ? null : component(map, "b"),
			a == null ? null : component(map, "a"));
	}

	/** Stores a vector, writing only the components the vector has. **/
	public function setVector(property:String, value:VectorData):Void
	{
		if (value == null)
		{
			putIn("m_Colors", property, null);
			return;
		}
		var map = new YamlMap(null, true);
		map.set("r", number(value.x));
		map.set("g", number(value.y));
		if (value.hasZ || value.z != null) map.set("b", number(value.z == null ? 0 : value.z));
		if (value.hasW || value.w != null) map.set("a", number(value.w == null ? 0 : value.w));
		putIn("m_Colors", property, map);
	}

	/** The float of [property], or `null`. **/
	public function getFloat(property:String):Null<Float>
	{
		var value = scalarOf("m_Floats", property);
		return value == null ? null : Scalars.tryFloat(value);
	}

	/** Stores a float. **/
	public function setFloat(property:String, value:Float):Void
	{
		putIn("m_Floats", property, number(value));
	}

	/** The int of [property], or `null`. **/
	public function getInt(property:String):Null<Int>
	{
		var value = scalarOf("m_Ints", property);
		return value == null ? null : Scalars.tryInt(value);
	}

	/** Stores an int. **/
	public function setInt(property:String, value:Int):Void
	{
		putIn("m_Ints", property, number(value));
	}

	/**
		Removes [property] from whichever list holds it.

		Returns the list's name, or `null` when the property was not set. Removal
		rather than zeroing is what the editor does when a shader stops declaring a
		property, and it is the only way to get an entry out of a material.
	**/
	public function removeProperty(property:String):String
	{
		for (list in ["m_TexEnvs", "m_Ints", "m_Floats", "m_Colors"])
		{
			var seq = listOf(list);
			if (seq == null) continue;
			for (i in 0...seq.items.length)
			{
				var entry = entryName(seq.items[i]);
				if (entry != property) continue;
				seq.removeAt(i);
				return list;
			}
		}
		return null;
	}

	// ---------------------------------------------------------------- internals

	/** Stores [value] as the entry of [property] in [list], or removes it. **/
	function putIn(list:String, property:String, value:YamlNode):Void
	{
		var existing = itemOf(list, property);
		if (existing != null)
		{
			if (value == null)
			{
				removeProperty(property);
				return;
			}
			// Replacing the value keeps the entry where it is, which is what
			// makes editing a material a one line change in the file.
			existing.set(property, value);
			return;
		}
		if (value == null) return;
		var item = new YamlMap();
		item.set(property, value);
		insert(list, property, item);
	}

	/**
		Inserts [entry] into [list] keeping the property names in order.

		Unity serialises these lists sorted by property name, so a new entry lands
		where Unity would put it. Appending instead would produce a file Unity
		rewrites the next time it imports the asset — the same content, a
		different file.
	**/
	function insert(list:String, property:String, item:YamlMap):Void
	{
		var seq = listOf(list);
		if (seq == null)
		{
			seq = new YamlSeq();
			fields().set(list, seq);
		}
		var at = seq.items.length;
		for (i in 0...seq.items.length)
		{
			var name = entryName(seq.items[i]);
			if (name != null && name > property)
			{
				at = i;
				break;
			}
		}
		seq.items.insert(at, item);
	}

	/**
		The one key mapping that holds [property] inside [list], or `null`.

		A list entry is `- _MainTex:` followed by the property's value, so the
		item itself is the mapping and its single key is the property name.
	**/
	function itemOf(list:String, property:String):YamlMap
	{
		var seq = listOf(list);
		if (seq == null) return null;
		for (item in seq.items)
		{
			if (!Std.isOfType(item, YamlMap)) continue;
			var map:YamlMap = cast item;
			if (map.entries.length == 0) continue;
			if (map.entries[0].key == property) return map;
		}
		return null;
	}

	/** The `{r, g, b, a}` mapping of a colour or vector property, or `null`. **/
	function colorMap(property:String):YamlMap
	{
		var item = itemOf("m_Colors", property);
		if (item == null) return null;
		var value = item.get(property);
		return (value != null && Std.isOfType(value, YamlMap)) ? cast value : null;
	}

	/** Scalar text of a property in [list], or `null`. **/
	function scalarOf(list:String, property:String):String
	{
		var item = itemOf(list, property);
		if (item == null) return null;
		var value = item.get(property);
		return value == null ? null : value.toString();
	}

	/** The sequence stored under [list], or `null`. **/
	function listOf(list:String):YamlSeq
	{
		var fields = fields();
		return fields == null ? null : fields.getSeq(list);
	}

	/** Property names in [list], in file order. **/
	function namesIn(list:String):Array<String>
	{
		var out = [];
		var seq = listOf(list);
		if (seq == null) return out;
		for (item in seq.items)
		{
			var name = entryName(item);
			if (name != null) out.push(name);
		}
		return out;
	}

	/** Name of a list entry, which is the key of its one key mapping. **/
	static function entryName(item:YamlNode):String
	{
		if (item == null || !Std.isOfType(item, YamlMap)) return null;
		var map:YamlMap = cast item;
		return map.entries.length == 0 ? null : map.entries[0].key;
	}

	static function component(map:YamlMap, key:String):Float
	{
		var text = map.getString(key);
		if (text == null) return 0;
		var value = Scalars.tryFloat(text);
		return value == null ? 0 : value;
	}

	static function number(value:Float):YamlScalar
	{
		return new YamlScalar(Numbers.format(value), ScalarKind.Plain);
	}
}
