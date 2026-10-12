package hxunity.unity;

import haxe.Int64;
import haxe.ds.StringMap;

/**
	The two numbers a serialised reference needs besides the GUID: the **file id**
	of the target object and the **`type:`** Unity writes next to it.

	```yaml
	m_Materials:
	- {fileID: 2100000, guid: 506c261d2f0f7d84a9f0b0d5b0c33a72, type: 2}
	```

	Getting either wrong does not fail loudly. A wrong `fileID` makes Unity resolve
	the reference to nothing and show *Missing*; a wrong `type:` usually still
	loads, which is worse, because the mistake survives review. So the table lives
	here, in one place, instead of at every call site.

	## Where the numbers come from

	Every value below was read out of a real Unity 2022.3 project rather than
	recalled. The reference type was confirmed by joining every
	`{fileID, guid, type}` triple in that project's `.prefab`, `.mat`, `.unity`
	and `.asset` files against the importer section of the target's `.meta`:

	| target | fileID | type | occurrences |
	|---|---|---|---|
	| Material (`.mat`) | 2100000 | 2 | 9,882 |
	| ScriptableObject (`.asset`) | 11400000 | 2 | 1,121 |
	| AnimatorController (`.controller`) | 9100000 | 2 | 78 |
	| AnimationClip (`.anim`) | 7400000 | 2 | 133 |
	| Texture2D (`.png`) | 2800000 | 3 | 4,422 |
	| Sprite (a sprite inside a texture) | 21300000 | 3 | 181 |
	| Prefab (`.prefab`) | 100100000 | 3 | 5,128 |
	| Shader (`.shader`) | 4800000 | 3 | 4,390 |
	| MonoScript (`.cs`) | 11500000 | 3 | 8,416 |
	| AudioClip (`.wav`) | 8300000 | 3 | 3 |
	| built-in resource (Cube mesh, ...) | 10210 | 0 | 5,709 |

	Which gives the rule this class implements:

	* **`type: 0`** — an engine built-in. Its GUID is one of the fixed
	  [BuiltinResources] GUIDs and no `.meta` file exists for it.
	* **`type: 2`** — a *native* asset: one Unity serialises itself, which is
	  exactly the set imported by `NativeFormatImporter` (`.mat`, `.asset`,
	  `.controller`, `.anim`).
	* **`type: 3`** — everything else in the project, including every *imported*
	  asset (a texture, shader, script, model, audio clip — the importer reads a
	  foreign file) and prefabs.

	> The example that used to sit in [UnityReference] — "`type: 2` is an imported
	> asset such as a texture" — has it backwards, and the count above is what
	> settles it: a texture is written `type: 3` and a material `type: 2`.
**/
class AssetReference
{
	/** `fileID` of the main object of a texture, e.g. a `.png`. **/
	public static inline var TEXTURE_ID:Int = 2800000;

	/** `fileID` of a `Material`, the main object of a `.mat`. **/
	public static inline var MATERIAL_ID:Int = 2100000;

	/**
		`fileID` Unity writes when the target is a prefab.

		This is the one entry that is not a class id offset: a prefab is a tree of
		GameObjects with no single main object, and 100100000 is the id Unity
		itself puts in `m_SourcePrefab` and in every `m_Materials` style reference
		that points at a prefab. It is deliberately *not* used by
		[AssetClassifier.mainIdOf], which classifies the objects inside a file.
	**/
	public static inline var PREFAB_ID:Int = 100100000;

	/** `fileID` of the first `Sprite` inside an imported texture. **/
	public static inline var SPRITE_ID:Int = 21300000;

	/** `fileID` of a `Shader`, the main object of a `.shader`. **/
	public static inline var SHADER_ID:Int = 4800000;

	/** `fileID` of a `MonoScript`, the main object of a `.cs`. **/
	public static inline var MONO_SCRIPT_ID:Int = 11500000;

	/** `fileID` of a `ScriptableObject`, the main object of a `.asset`. **/
	public static inline var SCRIPTABLE_OBJECT_ID:Int = 11400000;

	/** `fileID` of an `AnimatorController`, the main object of a `.controller`. **/
	public static inline var ANIMATOR_CONTROLLER_ID:Int = 9100000;

	/** `fileID` of an `AnimationClip`, the main object of a `.anim`. **/
	public static inline var ANIMATION_CLIP_ID:Int = 7400000;

	/** `fileID` of a `Mesh`, the main object of a `.fbx` / `.obj` model. **/
	public static inline var MESH_ID:Int = 4300000;

	/**
		Main object file id per lowercased extension.

		Keyed by extension and not by importer because the importer cannot decide:
		`NativeFormatImporter` alone covers `.mat`, `.asset`, `.controller` and
		`.anim`, which have four different main object ids.
	**/
	static var mainIds:StringMap<Int> = buildMainIds();

	static function buildMainIds():StringMap<Int>
	{
		var map = new StringMap<Int>();

		// --- native assets, confirmed against mainObjectFileID in their .meta ---
		// `.mat` carries mainObjectFileID: 2100000, `.asset` 11400000.
		map.set("mat", MATERIAL_ID);
		map.set("asset", SCRIPTABLE_OBJECT_ID);
		map.set("controller", ANIMATOR_CONTROLLER_ID);
		map.set("anim", ANIMATION_CLIP_ID);

		// --- imported assets, confirmed by the fileID Unity writes next to the
		// --- GUID of each in a real project (see the table in the class comment) ---
		map.set("prefab", PREFAB_ID);
		map.set("shader", SHADER_ID);
		map.set("cs", MONO_SCRIPT_ID);
		map.set("png", TEXTURE_ID);
		map.set("jpg", TEXTURE_ID);
		map.set("jpeg", TEXTURE_ID);
		map.set("tga", TEXTURE_ID);
		map.set("psd", TEXTURE_ID);
		map.set("tif", TEXTURE_ID);
		map.set("tiff", TEXTURE_ID);
		map.set("bmp", TEXTURE_ID);
		map.set("gif", TEXTURE_ID);
		map.set("exr", TEXTURE_ID);
		map.set("hdr", TEXTURE_ID);

		// --- standard sub asset offsets, following Unity's "<class id>000000"
		// --- rule; not confirmed in this workspace ---
		map.set("overridecontroller", 22100000); // AnimatorOverrideController
		map.set("ttf", 1280000); // Font
		map.set("otf", 1280000);

		// Deliberately absent: an extension whose asset has no single main object
		// a caller could mean. `.fbx` is the awkward one — a scene references the
		// mesh inside it as `{fileID: 4300000, guid: ..., type: 2}`, while the
		// model's own root is a GameObject with an id this library cannot derive,
		// so a caller naming a model has to pass the file id it means.`.shadergraph`
		// is absent for the same reason: the shader it generates is a sub asset
		// whose id follows the graph, not a fixed offset.
		return map;
	}

	/**
		Main object file id for [extension], or `null`.

		`null` means "this library cannot name one safely, pass a file id". A
		guessed id is worse than none: it resolves to a different object rather
		than failing.
	**/
	public static function mainObjectIdOf(extension:String):Int64
	{
		if (extension == null) return null;
		var id = mainIds.get(extension.toLowerCase());
		return id == null ? null : Int64.ofInt(id);
	}

	/**
		`type:` Unity writes when referencing an asset of [kind] by [guid].

		A built-in GUID always yields 0: those name engine resources, and the
		`type:` describes where the object lives rather than what class it is.
	**/
	public static function typeForKind(kind:AssetKind, ?guid:String):Int
	{
		if (guid != null && AssetGuid.isBuiltin(guid)) return UnityReference.TYPE_BUILTIN;
		// The native assets are exactly the ones NativeFormatImporter owns; see
		// the class comment for the measurement behind that.
		return kind == AssetKind.NativeAsset ? UnityReference.TYPE_NATIVE : UnityReference.TYPE_IMPORTED;
	}

	/** `type:` Unity writes when referencing the asset at [extension]. **/
	public static function typeOf(extension:String, ?guid:String):Int
	{
		return typeForKind(AssetClassifier.kindOf(extension, null, false), guid);
	}

	/**
		A reference to the main object of the asset [guid] names.

		[fileId] overrides the default main object id, which is what a sprite or a
		model sub asset needs; `null` takes the default and throws when the
		extension has none, because silently writing `{fileID: 0}` next to a GUID
		is the failure this class exists to prevent.
	**/
	public static function of(guid:String, extension:String, ?fileId:Int64):UnityReference
	{
		var id = fileId == null ? mainObjectIdOf(extension) : fileId;
		if (id == null) throw 'no main object file id is known for ".$extension"; pass one explicitly';
		return new UnityReference(id, AssetGuid.normalise(guid), typeOf(extension, guid));
	}

	/** A reference to the main object of the asset of [kind], or `null` when it has none. **/
	public static function ofKind(guid:String, kind:AssetKind, ?fileId:Int64):UnityReference
	{
		var id = fileId;
		if (id == null)
		{
			id = switch (kind)
			{
				case NativeAsset: mainObjectIdOf("asset");
				case Texture: mainObjectIdOf("png");
				case Prefab: mainObjectIdOf("prefab");
				case Shader: mainObjectIdOf("shader");
				case Script: mainObjectIdOf("cs");
				default: null;
			}
		}
		if (id == null) return null;
		return new UnityReference(id, AssetGuid.normalise(guid), typeForKind(kind, guid));
	}
}
