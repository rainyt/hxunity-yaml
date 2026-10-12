package hxunity.unity;

import haxe.Int64;

/**
	Turns a parsed `.meta` file plus an asset path into an [AssetEntry].

	Two decisions happen here, and both need more than the `.meta` file alone:

	* **kind** — `NativeFormatImporter` is shared by `.mat`, `.asset`,
	  `.controller` and `.anim`, so the importer name only narrows it down and the
	  extension decides.
	* **main object id** — Unity writes `mainObjectFileID` for
	  `NativeFormatImporter` only, so two thirds of assets need the id inferred
	  from the importer and extension instead. The table itself lives in
	  [AssetReference], which is also where the `type:` Unity writes for each
	  asset type is recorded.
**/
class AssetClassifier
{
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

	/**
		Main object file id for [extension], or `null` when there is no such thing.

		Public because a caller building a reference needs the id without a
		[MetaFile] in hand — see [hxunity.unity.AssetReference], which also knows
		the `type:` that goes with it. Anything absent is `null` on purpose: a
		wrong id makes a resolver report the wrong object, while `null` merely
		says "ask the file".
	**/
	public static function mainObjectIdOf(extension:String):Int64
	{
		return AssetReference.mainObjectIdOf(extension);
	}

	/** Main object file id, from the `.meta` file when present, else inferred. **/
	public static function mainIdOf(meta:MetaFile, extension:String, kind:AssetKind):Int64
	{
		if (meta != null && meta.mainObjectFileId != null) return meta.mainObjectFileId;
		if (kind == AssetKind.Folder || kind == AssetKind.Unknown) return null;
		// A prefab is a tree of GameObjects, so there is no single object an id
		// could name inside it. [AssetReference.PREFAB_ID] exists for the other
		// direction — a reference *to* a prefab — and saying "this document is
		// the main object" for every prefab reference would be false.
		if (kind == AssetKind.Prefab) return null;

		// Keyed by extension only: the importer cannot identify a main object,
		// because NativeFormatImporter alone covers `.mat`, `.asset`,
		// `.controller` and `.anim`, which have four different ids.
		return AssetReference.mainObjectIdOf(extension);
	}

}
