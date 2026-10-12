package hxunity.unity;

import haxe.Int64;
import hxunity.prefab.UnityObject;
import hxunity.prefab.UnityPrefab;
import hxunity.types.ColorData;
import hxunity.types.VectorData;
import hxunity.yaml.ClassIds;
import hxunity.yaml.UnityDocumentSet;
import hxunity.yaml.UnityYamlDocument;
import hxunity.yaml.YamlMap;

/**
	A `.mat` file: one document, one `Material`, and the texture assignments that
	make a renderer draw something.

	```haxe
	var material = UnityMaterial.create(shaderGuid, "hand");
	material.setTexture("_MainTex", textureGuid);
	material.setVector("_Pivot", new VectorData(0.5, 0.5));
	material.save("Assets/Psd/Hero/hand.mat");
	```

	## Why not the document API

	Building this by hand means writing out `serializedVersion: 8`, the twenty
	render state fields Unity expects, a `m_SavedProperties` block with four
	lists, and a `m_Shader` reference with the right file id and `type:` — every
	one of which fails quietly when wrong. The editor's own material reader looks
	at `m_CustomRenderQueue`, `m_Shader` and `m_SavedProperties.m_TexEnvs`, so a
	generated `.mat` that is missing any of them reads as "material with no
	texture".

	## Field sets come from real files

	The document a new material starts as is [hxunity.unity.ComponentDefaults.material],
	whose fields and order are copied from a Unity 2022.3.62 project. When a
	project has its own material template, [fromTemplate] starts from that
	instead — the same trick as [MetaWriter.rewriteGuid], and the one with the
	best chance of Unity leaving the file alone.
**/
class UnityMaterial
{
	/** The document set that holds the material, so other documents survive. **/
	public var prefab(default, null):UnityPrefab;

	/** The `Material` document itself. **/
	public var document(default, null):UnityYamlDocument;

	/** Path the material was read from, or `null` when it was created in memory. **/
	public var path(default, null):String;

	var propertiesCache:MaterialProperties;

	function new(prefab:UnityPrefab, document:UnityYamlDocument, ?path:String)
	{
		this.prefab = prefab;
		this.document = document;
		this.path = path;
	}

	/**
		An empty material.

		[shaderGuid] is the shader to reference; omitting it writes Unity's
		built-in Standard shader, which is what an empty "New Material" carries in
		the editor. [name] is the `m_Name` field, which is what the project window
		shows and not the file name.
	**/
	public static function create(?shaderGuid:String, ?name:String):UnityMaterial
	{
		var set = UnityDocumentSet.createEmpty();
		var document = new UnityYamlDocument(ClassIds.Material, Int64.ofInt(AssetReference.MATERIAL_ID), false,
			wrap("Material", ComponentDefaults.material(name, shaderReferenceOf(shaderGuid))), 0, true, true);
		set.add(document);
		return new UnityMaterial(new UnityPrefab(set), document);
	}

	/**
		Reads a `.mat` file.

		Every document in the file is kept, not only the `Material`: a `.mat`
		exported by a URP project also carries a `MonoBehaviour` that names the
		shader's version, and dropping it would change how the material imports.
	**/
	public static function fromFile(path:String):UnityMaterial
	{
		var loaded = UnityPrefab.fromFile(path);
		var document = loaded.firstDocumentOfClass(ClassIds.Material);
		if (document == null) throw '"$path" holds no Material document';
		return new UnityMaterial(loaded, document, path);
	}

	/** Reads a material from text, with no path to save back to. **/
	public static function fromText(text:String):UnityMaterial
	{
		var loaded = UnityPrefab.parse(text);
		var document = loaded.firstDocumentOfClass(ClassIds.Material);
		if (document == null) throw "the text holds no Material document";
		return new UnityMaterial(loaded, document);
	}

	/**
		Starts from a copy of the `.mat` at [templatePath].

		The copy keeps the template's shader, its render state and its
		`serializedVersion`; only the fields the caller then sets change. This is
		how a project's own material (URP Lit, a custom shader) is used as the
		starting point for a generated one.
	**/
	public static function fromTemplate(templatePath:String):UnityMaterial
	{
		return fromFile(templatePath);
	}

	/** The material document as an object, for the inherited field accessors. **/
	public function object():UnityObject
	{
		return prefab.componentByDocument(document);
	}

	/** Its `m_SavedProperties`, created empty when the material has none. **/
	public function properties():MaterialProperties
	{
		if (propertiesCache == null) propertiesCache = MaterialProperties.ensure(object());
		return propertiesCache;
	}

	/**
		The file id of the `Material` object.

		`2100000` for a material this library creates, which is the id Unity uses
		and therefore the id references to it carry. A material read from a file
		keeps whatever id that file declared.
	**/
	public function mainObjectFileId():Int64
	{
		return document.fileId;
	}

	// ----------------------------------------------------------------- the basics

	/** `m_Name`. **/
	public function name():String
	{
		return object().getString("m_Name");
	}

	/** Sets `m_Name`. **/
	public function setName(value:String):Void
	{
		object().setString("m_Name", value);
	}

	/** The `m_Shader` reference, or `null`. **/
	public function shader():UnityReference
	{
		return object().getReference("m_Shader");
	}

	/** Assigns a project shader. **/
	public function setShader(guid:String, ?fileId:Int64, ?type:Int):Void
	{
		object().setReference("m_Shader", UnityReference.shader(guid));
		if (fileId == null && type == null) return;
		// An explicit file id or type overrides the shader defaults, which is what
		// a shader graph or a package shader needs.
		var id = fileId == null ? AssetReference.mainObjectIdOf("shader") : fileId;
		var kind = type == null ? UnityReference.TYPE_IMPORTED : type;
		object().setReference("m_Shader", new UnityReference(id, AssetGuid.normalise(guid), kind));
	}

	/** Assigns one of Unity's built-in shaders by its file id. **/
	public function setBuiltinShader(fileId:Int):Void
	{
		object().setReference("m_Shader", UnityReference.builtin(Int64.ofInt(fileId)));
	}

	/**
		`m_CustomRenderQueue`.

		`-1` means "let the shader's `Queue` tag decide", which is what Unity
		writes for a material that has not overridden the queue. A consumer that
		needs a concrete number has to read the shader for it — which is exactly
		what the editor's renderer does, and why a generated material should leave
		this at `-1` unless it means to override.
	**/
	public function renderQueue():Int
	{
		var value = object().getInt("m_CustomRenderQueue");
		return value == null ? -1 : value;
	}

	/** Sets `m_CustomRenderQueue`; use `-1` to hand the decision to the shader. **/
	public function setRenderQueue(value:Int):Void
	{
		object().setInt("m_CustomRenderQueue", value);
	}

	// --------------------------------------------------------------- properties

	/** GUID of the texture assigned to [property], or `null`. **/
	public function getTexture(property:String):String
	{
		return properties().getTexture(property);
	}

	/** Assigns [guid] to [property], e.g. `_MainTex` or `_BaseMap`. **/
	public function setTexture(property:String, guid:String, ?fileId:Int64, ?type:Int, ?scale:VectorData, ?offset:VectorData):Void
	{
		properties().setTexture(property, guid, fileId, type, scale, offset);
	}

	/** Clears the texture assigned to [property]. **/
	public function clearTexture(property:String):Void
	{
		properties().clearTexture(property);
	}

	/** The colour of [property], or `null`. **/
	public function getColor(property:String):ColorData
	{
		return properties().getColor(property);
	}

	/** Stores a colour property, e.g. `_Color`. **/
	public function setColor(property:String, value:ColorData):Void
	{
		properties().setColor(property, value);
	}

	/** Stores a float property, e.g. `_Cutoff`. **/
	public function setFloat(property:String, value:Float):Void
	{
		properties().setFloat(property, value);
	}

	/** Stores an int property. **/
	public function setInt(property:String, value:Int):Void
	{
		properties().setInt(property, value);
	}

	/**
		Stores a vector property.

		Unity keeps a shader's `Vector` properties in `m_Colors`, written with the
		component names `r` / `g` / `b` / `a`. A `Vector2` is written two
		components wide, so `setVector("_Pivot", new VectorData(0.5, 0.5))` yields
		`- _Pivot: {r: 0.5, g: 0.5}`, the shape the editor's material reader
		expects.
	**/
	public function setVector(property:String, value:VectorData):Void
	{
		properties().setVector(property, value);
	}

	/** The vector of [property], or `null`. **/
	public function getVector(property:String):VectorData
	{
		return properties().getVector(property);
	}

	/** Removes [property] from whichever list holds it. **/
	public function removeProperty(property:String):String
	{
		return properties().removeProperty(property);
	}

	// ------------------------------------------------------------------ writing

	/** The whole `.mat` file as text, `%YAML` preamble included. **/
	public function emit():String
	{
		return prefab.emit();
	}

	/**
		Writes the file, atomically, to [path] or to the path it was read from.

		A material created in memory has no path, so [save] without one throws
		rather than writing somewhere unintended.
	**/
	public function save(?path:String):Void
	{
		var target = path == null ? this.path : path;
		if (target == null) throw "UnityMaterial.save needs a path";
		if (!AssetWriter.saveText(target, emit())) throw 'cannot write the material to "$target"';
	}

	/** Deep copy, with no path, so a copy cannot overwrite its source. **/
	public function clone():UnityMaterial
	{
		var copy = prefab.deepClone();
		return new UnityMaterial(copy, copy.firstDocumentOfClass(ClassIds.Material));
	}

	static function shaderReferenceOf(guid:String):UnityReference
	{
		return guid == null ? null : UnityReference.shader(guid);
	}

	/** Wraps [fields] in the single class-name key a Unity document body has. **/
	static function wrap(className:String, fields:YamlMap):YamlMap
	{
		var body = new YamlMap();
		body.set(className, fields);
		return body;
	}

	public function toString():String
	{
		return 'UnityMaterial(${name()}, ${path == null ? "<memory>" : path})';
	}
}
