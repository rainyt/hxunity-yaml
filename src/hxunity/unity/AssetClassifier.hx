package hxunity.unity;

import haxe.Int64;
import haxe.ds.StringMap;

/**
	Turns a parsed `.meta` file plus an asset path into an [AssetEntry].

	Two decisions happen here, and both need more than the `.meta` file alone:

	* **kind** — `NativeFormatImporter` is shared by `.mat`, `.asset`,
	  `.controller` and `.anim`, so the importer name only narrows it down and the
	  extension decides.
	* **main object id** — Unity writes `mainObjectFileID` for
	  `NativeFormatImporter` only, so two thirds of assets need the id inferred
	  from the importer and extension instead.
**/
class AssetClassifier
{
	/**
		File id of the main object, keyed by `"<extension>|<importer>"`.

		Unity has never documented these as an API, so the tiers are recorded in the
		comments. Anything absent is left `null` on purpose: a wrong id would make a
		resolver report the wrong object, while `null` merely says "ask the file".
	**/
	static var MAIN_IDS:StringMap<Int> = buildMainIds();

	/** Builds an entry from a `.meta` file and the asset's project relative path. **/
	public static function build(meta:MetaFile, assetPath:String, origin:Origin):AssetEntry
	{
		var path = AssetGuidIndex.normalisePath(assetPath);
		var extension = extensionOf(path);
		var kind = kindOf(extension, meta.importer, meta.isFolder);
		var mainId = mainIdOf(meta, extension, kind);
		return new AssetEntry(meta.guid, path, kind, origin, mainId, meta.importer);
	}

	/** Where an asset path lives, decided by its leading path segments. **/
	public static function originOf(assetPath:String):Origin
	{
		if (assetPath == null) return Origin.Missing;
		var path = AssetGuidIndex.normalisePath(assetPath);
		if (StringTools.startsWith(path, "Assets/")) return Origin.Project;
		if (StringTools.startsWith(path, "Packages/")) return Origin.Package;
		// A package resolved from the cache is still a package, not project content.
		if (path.indexOf("PackageCache/") >= 0) return Origin.Package;
		return Origin.Project;
	}

	/** Lowercase extension of [path] without the dot, or `null`. **/
	public static function extensionOf(path:String):String
	{
		if (path == null) return null;
		var name = path;
		var slash = name.lastIndexOf("/");
		if (slash >= 0) name = name.substr(slash + 1);
		var dot = name.lastIndexOf(".");
		return dot < 0 ? null : name.substr(dot + 1).toLowerCase();
	}

	/** Kind implied by the extension and importer. **/
	public static function kindOf(extension:String, importer:String, isFolder:Bool):AssetKind
	{
		if (isFolder) return AssetKind.Folder;
		// A folder is the one thing DefaultImporter is used for.
		if (importer == "DefaultImporter") return AssetKind.Folder;

		// The importer family is the strong signal; the extension breaks ties.
		switch (importer)
		{
			case "TextureImporter":
				return AssetKind.Texture;
			case "ModelImporter":
				return AssetKind.Model;
			case "PrefabImporter":
				return AssetKind.Prefab;
			case "MonoImporter", "AssemblyDefinitionImporter":
				return AssetKind.Script;
			case "TextScriptImporter":
				return AssetKind.Text;
			case "AudioImporter":
				return AssetKind.Audio;
			case "VideoClipImporter":
				return AssetKind.Video;
			case "ShaderImporter":
				return AssetKind.Shader;
			case "TrueTypeFontImporter":
				return AssetKind.Font;
			case "PluginImporter":
				return AssetKind.Plugin;
			case "NativeFormatImporter", null:
				// Nothing more to learn from the importer.
			default:
				// An importer this build has not seen; fall through to the
				// extension so a new Unity importer still classifies usefully.
		}

		return switch (extension)
		{
			case "prefab": AssetKind.Prefab;
			case "cs", "asmdef", "asmref": AssetKind.Script;
			case "mat", "asset", "controller", "anim", "overridecontroller", "playable", "mixer", "physicsmaterial2d": AssetKind.NativeAsset;
			case "png", "jpg", "jpeg", "tga", "psd", "tif", "tiff", "bmp", "gif", "exr", "hdr", "iff": AssetKind.Texture;
			case "fbx", "obj", "dae", "3ds", "dxf", "blend": AssetKind.Model;
			case "shader", "cginc", "hlsl", "compute", "glslinc": AssetKind.Shader;
			case "wav", "mp3", "ogg", "aiff", "aif", "flac", "mod", "it", "s3m", "xm": AssetKind.Audio;
			case "mp4", "mov", "webm", "avi", "asf", "m4v", "mpg", "mpeg": AssetKind.Video;
			case "ttf", "otf", "fontsettings": AssetKind.Font;
			case "txt", "json", "xml", "csv", "html", "htm", "yaml", "yml", "md", "bytes": AssetKind.Text;
			case "dll", "so", "dylib", "bundle", "aar", "jar", "a": AssetKind.Plugin;
			case null: AssetKind.Unknown;
			default: AssetKind.Unknown;
		}
	}

	/** Main object file id, from the `.meta` file when present, else inferred. **/
	public static function mainIdOf(meta:MetaFile, extension:String, kind:AssetKind):Int64
	{
		if (meta != null && meta.mainObjectFileId != null) return meta.mainObjectFileId;
		if (kind == AssetKind.Folder || kind == AssetKind.Unknown) return null;

		var byExtension = MAIN_IDS.get(extension == null ? "" : extension);
		if (byExtension != null) return Int64.ofInt(byExtension);

		// Keyed with a leading `|` so an importer name can never collide with an
		// extension that happens to be spelled the same.
		if (meta != null && meta.importer != null)
		{
			var byImporter = MAIN_IDS.get("|" + meta.importer);
			if (byImporter != null) return Int64.ofInt(byImporter);
		}

		return null;
	}

	static function buildMainIds():StringMap<Int>
	{
		var map = new StringMap<Int>();

		// --- observed in the reference project, alongside mainObjectFileID ---
		// `.mat` carries mainObjectFileID: 2100000.
		map.set("mat", 2100000);
		// ScriptableObjects carry mainObjectFileID: 11400000.
		map.set("asset", 11400000);
		// `.cs` is a MonoScript.
		map.set("cs", 11500000);

		// --- standard Unity sub asset offsets, not verified in this workspace ---
		// These follow Unity's "<class id>000000" convention for the first sub
		// asset, which is what the examples in Unity's own documentation show.
		map.set("controller", 9100000); // AnimatorController
		map.set("overridecontroller", 22100000); // AnimatorOverrideController
		map.set("anim", 7400000); // AnimationClip
		map.set("shader", 4800000); // Shader
		map.set("ttf", 1280000); // Font
		map.set("otf", 1280000);
		map.set("png", 2800000); // Texture2D
		map.set("jpg", 2800000);
		map.set("jpeg", 2800000);
		map.set("tga", 2800000);
		map.set("psd", 2800000);
		map.set("tif", 2800000);
		map.set("tiff", 2800000);
		map.set("bmp", 2800000);
		map.set("gif", 2800000);
		map.set("exr", 2800000);
		map.set("hdr", 2800000);

		// --- deliberately absent ---
		// `.prefab` has no main object: a prefab is a tree of GameObjects, so there
		// is no single object a `{guid, fileID}` could be defaulted to. `.fbx` and
		// the other model formats likewise name their contents per sub asset.
		return map;
	}
}
