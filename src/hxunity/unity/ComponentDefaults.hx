package hxunity.unity;

import haxe.Int64;
import hxunity.types.ColorData;
import hxunity.types.QuaternionData;
import hxunity.types.VectorData;
import hxunity.yaml.ClassIds;
import hxunity.yaml.ScalarKind;
import hxunity.yaml.Scalars;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.YamlSeq;

/**
	The fields Unity itself writes when it creates an object, per class.

	## Why this is needed

	`addComponent` used to write only the fields every `Component` shares, so a
	generated `MeshRenderer` came out with no `m_Materials` and no
	`m_SortingOrder`. Unity does not reject such a file: it fills the missing
	fields with defaults **and rewrites the whole document**, so the prefab an
	exporter just wrote is not the prefab Unity keeps. A consumer that reads
	`m_Materials` before Unity has touched the file — which is what this library's
	renderer does — finds nothing.

	So every class this library can create has its field set here, taken from a
	Unity 2022.3.62 project rather than from memory, in the order that project
	writes them.

	## The boundary

	These templates are used **only when an object is created**. Nothing here is
	ever applied to an object that was parsed from a file: injecting a field into
	a parsed document would break the byte-for-byte round trip that the whole
	library rests on, because the field would appear in the output where Unity
	never wrote one.
**/
class ComponentDefaults
{
	/**
		`fileID` of Unity's built-in Default-Material.

		What a new `MeshRenderer` gets: Unity never leaves a renderer with an
		empty material list, and a reference to the engine's own material is what
		it writes instead.
	**/
	public static inline var DEFAULT_MATERIAL_ID = 10303;

	/** `fileID` of Unity's built-in Sprites-Default material, for [SpriteRenderer]. **/
	public static inline var SPRITES_DEFAULT_MATERIAL_ID = 10754;

	/** True when [classId] has class specific defaults here. **/
	public static function hasTemplate(classId:Int):Bool
	{
		return switch (classId)
		{
			case ClassIds.GameObject, ClassIds.Transform, ClassIds.RectTransform, ClassIds.MeshRenderer, ClassIds.MeshFilter,
				ClassIds.SpriteRenderer, ClassIds.SortingGroup, ClassIds.Material, ClassIds.MonoBehaviour:
				true;
			default: false;
		}
	}

	/**
		Adds the class specific fields of [classId] that [fields] does not have.

		A field that is already present is left alone, so this can run over a map a
		caller has already written into.
	**/
	public static function apply(classId:Int, fields:YamlMap):Void
	{
		if (fields == null) return;
		switch (classId)
		{
			case ClassIds.MeshRenderer:
				renderer(fields, DEFAULT_MATERIAL_ID, 1, 2, 3);
				put(fields, "m_AdditionalVertexStreams", reference(0));
			case ClassIds.SpriteRenderer:
				renderer(fields, SPRITES_DEFAULT_MATERIAL_ID, 0, 0, 0);
				put(fields, "m_Sprite", reference(0));
				put(fields, "m_Color", new ColorData(1, 1, 1, 1).toNode());
				put(fields, "m_FlipX", number(0));
				put(fields, "m_FlipY", number(0));
				put(fields, "m_DrawMode", number(0));
				put(fields, "m_Size", new VectorData(1, 1).toNode());
				put(fields, "m_AdaptiveModeThreshold", number(0.5));
				put(fields, "m_SpriteTileMode", number(0));
				put(fields, "m_WasSpriteAssigned", number(0));
				put(fields, "m_MaskInteraction", number(0));
				put(fields, "m_SpriteSortPoint", number(1));
			case ClassIds.MeshFilter:
				// Left empty on purpose: a MeshFilter with no mesh is a state the
				// editor shows as "None (Mesh)" and leaves as it is, while naming
				// some built-in mesh would silently render the wrong thing.
				put(fields, "m_Mesh", reference(0));
			case ClassIds.SortingGroup:
				sorting(fields);
				put(fields, "m_SortAtRoot", number(0));
			case ClassIds.Material:
				materialDefaults(fields);
			case ClassIds.Transform:
				transformDefaults(fields, false);
			case ClassIds.RectTransform:
				transformDefaults(fields, true);
			default:
				// A class with no template keeps the common fields only, which is
				// what it got before: Unity fills the rest in and rewrites.
		}
	}

	/**
		The common header of a component document.

		Written first by every creation path, because these five fields — the hide
		flags, the three prefab references and the owning GameObject — are what
		make a component part of the file at all.
	**/
	public static function componentFields(classId:Int, gameObjectId:Int64):YamlMap
	{
		var fields = new YamlMap();
		fields.set("m_ObjectHideFlags", number(0));
		fields.set("m_CorrespondingSourceObject", reference(0));
		fields.set("m_PrefabInstance", reference(0));
		fields.set("m_PrefabAsset", reference(0));
		fields.set("m_GameObject", UnityReference.local(gameObjectId).toNode());
		if (writesEnabled(classId))
		{
			fields.set("m_Enabled", number(1));
		}
		return fields;
	}

	/**
		True when Unity writes `m_Enabled` for [classId].

		This is deliberately not [ClassIds.isBehaviour]: a `Renderer` is not a
		`Behaviour` in Unity's type hierarchy, yet every renderer serialises
		`m_Enabled`, and so does a `SortingGroup`. Writing it for the classes Unity
		leaves without one would be as wrong as omitting it here.
	**/
	public static function writesEnabled(classId:Int):Bool
	{
		if (ClassIds.isBehaviour(classId)) return true;
		return switch (classId)
		{
			case ClassIds.MeshRenderer, ClassIds.SpriteRenderer, ClassIds.TrailRenderer, ClassIds.LineRenderer,
				ClassIds.ParticleSystemRenderer, ClassIds.SortingGroup:
				true;
			default:
				false;
		}
	}

	/**
		The fields of a `GameObject` document.

		`serializedVersion: 6` and the field order are Unity 2022.3's; the
		transform is listed in `m_Component` before anything else, which is the
		order Unity's own writer uses.
	**/
	public static function gameObject(name:String, transformId:Int64):YamlMap
	{
		var fields = new YamlMap();
		fields.set("m_ObjectHideFlags", number(0));
		fields.set("m_CorrespondingSourceObject", reference(0));
		fields.set("m_PrefabInstance", reference(0));
		fields.set("m_PrefabAsset", reference(0));
		fields.set("serializedVersion", number(6));
		var components = new YamlSeq();
		var entry = new YamlMap();
		entry.set("component", UnityReference.local(transformId).toNode());
		components.push(entry);
		fields.set("m_Component", components);
		fields.set("m_Layer", number(0));
		fields.set("m_Name", Scalars.ofString(name));
		fields.set("m_TagString", plain("Untagged"));
		fields.set("m_Icon", reference(0));
		fields.set("m_NavMeshLayer", number(0));
		fields.set("m_StaticEditorFlags", number(0));
		fields.set("m_IsActive", number(1));
		return fields;
	}

	/**
		The fields of a `Transform` (or `RectTransform`) document.

		[parentTransformId] writes `m_Father`; `null` means a root object, written
		as `{fileID: 0}`. A `RectTransform` adds the five layout fields and, unlike
		a `Transform`, writes no `serializedVersion` — both details confirmed
		against Unity 2022.3 output.
	**/
	public static function transform(gameObjectId:Int64, parentTransformId:Int64, rect:Bool):YamlMap
	{
		var fields = new YamlMap();
		fields.set("m_ObjectHideFlags", number(0));
		fields.set("m_CorrespondingSourceObject", reference(0));
		fields.set("m_PrefabInstance", reference(0));
		fields.set("m_PrefabAsset", reference(0));
		fields.set("m_GameObject", UnityReference.local(gameObjectId).toNode());
		if (!rect) fields.set("serializedVersion", number(2));
		fields.set("m_LocalRotation", new QuaternionData(0, 0, 0, 1).toNode());
		fields.set("m_LocalPosition", new VectorData(0, 0, 0).toNode());
		fields.set("m_LocalScale", new VectorData(1, 1, 1).toNode());
		fields.set("m_ConstrainProportionsScale", number(0));
		fields.set("m_Children", new YamlSeq());
		fields.set("m_Father",
			parentTransformId == null ? reference(0) : UnityReference.local(parentTransformId).toNode());
		fields.set("m_LocalEulerAnglesHint", new VectorData(0, 0, 0).toNode());
		if (rect)
		{
			fields.set("m_AnchorMin", new VectorData(0, 0).toNode());
			fields.set("m_AnchorMax", new VectorData(0, 0).toNode());
			fields.set("m_AnchoredPosition", new VectorData(0, 0).toNode());
			fields.set("m_SizeDelta", new VectorData(100, 100).toNode());
			fields.set("m_Pivot", new VectorData(0.5, 0.5).toNode());
		}
		return fields;
	}

	/** The `Transform` fields of a document that already has its GameObject reference. **/
	static function transformDefaults(fields:YamlMap, rect:Bool):Void
	{
		var gameObject = UnityReference.fromNode(fields.get("m_GameObject"));
		var parent = UnityReference.fromNode(fields.get("m_Father"));
		var template = transform(gameObject == null ? FileId.zeroId() : gameObject.fileId, parent == null || parent.isNone() ? null : parent.fileId,
			rect);
		for (entry in template.entries)
		{
			put(fields, entry.key, entry.value);
		}
	}

	/**
		The fields of a `Material` document.

		`serializedVersion: 8`, and the whole set of render state fields Unity
		writes even when they hold their defaults: an importer that finds them
		missing adds them back and rewrites the file. `m_CustomRenderQueue: -1`
		hands the queue decision to the shader, which is what Unity means by
		"default".
	**/
	public static function material(name:String, ?shader:UnityReference):YamlMap
	{
		var fields = new YamlMap();
		fields.set("serializedVersion", number(8));
		fields.set("m_ObjectHideFlags", number(0));
		fields.set("m_CorrespondingSourceObject", reference(0));
		fields.set("m_PrefabInstance", reference(0));
		fields.set("m_PrefabAsset", reference(0));
		fields.set("m_Name", Scalars.ofString(name == null ? "New Material" : name));
		fields.set("m_Shader", (shader == null ? builtinShader() : shader).toNode());
		fields.set("m_Parent", reference(0));
		fields.set("m_ModifiedSerializedProperties", number(0));
		fields.set("m_ValidKeywords", new YamlSeq());
		fields.set("m_InvalidKeywords", new YamlSeq());
		fields.set("m_LightmapFlags", number(4));
		fields.set("m_EnableInstancingVariants", number(0));
		fields.set("m_DoubleSidedGI", number(0));
		fields.set("m_CustomRenderQueue", number(-1));
		fields.set("stringTagMap", new YamlMap(null, true));
		fields.set("disabledShaderPasses", new YamlSeq());
		fields.set("m_LockedProperties", plain(""));
		var properties = new YamlMap();
		properties.set("serializedVersion", number(3));
		properties.set("m_TexEnvs", new YamlSeq());
		properties.set("m_Ints", new YamlSeq());
		properties.set("m_Floats", new YamlSeq());
		properties.set("m_Colors", new YamlSeq());
		fields.set("m_SavedProperties", properties);
		fields.set("m_BuildTextureStacks", new YamlSeq());
		return fields;
	}

	/** Fills in the defaults of a `Material` mapping that is already partly built. **/
	static function materialDefaults(fields:YamlMap):Void
	{
		var name = fields.getString("m_Name");
		var shader = UnityReference.fromNode(fields.get("m_Shader"));
		var template = material(name, shader);
		for (entry in template.entries)
		{
			put(fields, entry.key, entry.value);
		}
	}

	/** Unity's built-in Standard shader, the default of a material with no shader. **/
	static function builtinShader():UnityReference
	{
		// fileID 46 with the built-in resources GUID, which is what an empty
		// "New Material" carries in a real project.
		return UnityReference.builtin(Int64.ofInt(46));
	}

	/**
		The fields a `Renderer` shares, as Unity writes them.

		[materialId] is the built-in material a new renderer of this class starts
		with, [castShadows] / [rayTracingMode] / [editorRenderState] the three
		values that differ between a mesh renderer and a sprite one.
	**/
	static function renderer(fields:YamlMap, materialId:Int, castShadows:Int, rayTracingMode:Int, editorRenderState:Int):Void
	{
		put(fields, "m_CastShadows", number(castShadows));
		put(fields, "m_ReceiveShadows", number(castShadows));
		put(fields, "m_DynamicOccludee", number(1));
		put(fields, "m_StaticShadowCaster", number(0));
		put(fields, "m_MotionVectors", number(1));
		put(fields, "m_LightProbeUsage", number(1));
		put(fields, "m_ReflectionProbeUsage", number(1));
		put(fields, "m_RayTracingMode", number(rayTracingMode));
		put(fields, "m_RayTraceProcedural", number(0));
		put(fields, "m_RenderingLayerMask", number(1));
		put(fields, "m_RendererPriority", number(0));
		var materials = new YamlSeq();
		materials.push(UnityReference.builtin(Int64.ofInt(materialId)).toNode());
		put(fields, "m_Materials", materials);
		var batch = new YamlMap();
		batch.set("firstSubMesh", number(0));
		batch.set("subMeshCount", number(0));
		put(fields, "m_StaticBatchInfo", batch);
		put(fields, "m_StaticBatchRoot", reference(0));
		put(fields, "m_ProbeAnchor", reference(0));
		put(fields, "m_LightProbeVolumeOverride", reference(0));
		put(fields, "m_ScaleInLightmap", number(1));
		put(fields, "m_ReceiveGI", number(1));
		put(fields, "m_PreserveUVs", number(0));
		put(fields, "m_IgnoreNormalsForChartDetection", number(0));
		put(fields, "m_ImportantGI", number(0));
		put(fields, "m_StitchLightmapSeams", number(1));
		put(fields, "m_SelectedEditorRenderState", number(editorRenderState));
		put(fields, "m_MinimumChartSize", number(4));
		put(fields, "m_AutoUVMaxDistance", number(0.5));
		put(fields, "m_AutoUVMaxAngle", number(89));
		put(fields, "m_LightmapParameters", reference(0));
		sorting(fields);
	}

	/** `m_SortingLayerID` / `m_SortingLayer` / `m_SortingOrder`, shared by renderers. **/
	static function sorting(fields:YamlMap):Void
	{
		put(fields, "m_SortingLayerID", number(0));
		put(fields, "m_SortingLayer", number(0));
		put(fields, "m_SortingOrder", number(0));
	}

	/** Stores [value] under [key] unless the field is already there. **/
	static function put(fields:YamlMap, key:String, value:hxunity.yaml.YamlNode):Void
	{
		if (fields.has(key)) return;
		fields.set(key, value);
	}

	static function reference(fileId:Int):YamlMap
	{
		return UnityReference.local(Int64.ofInt(fileId)).toNode();
	}

	static function number(value:Float):YamlScalar
	{
		return new YamlScalar(hxunity.types.Numbers.format(value), ScalarKind.Plain);
	}

	static function plain(text:String):YamlScalar
	{
		return Scalars.ofString(text);
	}
}
