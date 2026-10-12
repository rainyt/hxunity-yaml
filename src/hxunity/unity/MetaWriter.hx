package hxunity.unity;

import haxe.Int64;

/**
	Creating `.meta` files.

	## Why a template rather than a field list

	A `.meta` file is the importer's entire state — a `TextureImporter` section is
	127 lines — and Unity rewrites it whenever it finds a field it disagrees with.
	A file assembled from a partial list of fields therefore does not stay the way
	it was written: importing the asset adds the missing fields back, which shows
	up as a whole-file diff on a file the exporter considered finished.

	So every factory here starts from a `.meta` Unity itself wrote and changes only
	what the caller asked for:

	* [forTexture] starts from [textureTemplate] — a real Unity 2022.3.62
	  `TextureImporter` block, kept in this file line for line, and also kept as a
	  test fixture so the two can be compared;
	* [rewriteGuid] starts from any `.meta` the caller names, which is how a
	  project's own import settings (compression, sprite sheet, platform
	  overrides) are carried onto a new asset;
	* the three small importers — folder, native asset, prefab — are short enough
	  to be written out in full, in Unity's field order, and are checked against
	  real `.meta` files rather than recalled.

	## What the caller still has to decide

	The GUID: [AssetGuid.generate] or [AssetGuidIndex.newGuid]. Nothing here
	invents one, because only the caller knows whether the GUIDs of the files it
	is writing have to be unique against an index.
**/
class MetaWriter
{
	/**
		A Unity 2022.3.62 `TextureImporter` `.meta`, as Unity wrote it.

		Copied verbatim from a real project (the GUID is replaced with the all zero
		placeholder), which is the point: `serializedVersion: 13` and the field
		order below are what that editor writes, and they are read off a file
		rather than remembered. `tests/fixtures/Unity2022/Textures/hand.png.meta`
		is the same file, and the test suite asserts that what this generates still
		matches it field for field.
	**/
	public static var textureTemplateLines(default, null):Array<String> = [
		"fileFormatVersion: 2",
		"guid: 00000000000000000000000000000000",
		"TextureImporter:",
		"  internalIDToNameTable: []",
		"  externalObjects: {}",
		"  serializedVersion: 13",
		"  mipmaps:",
		"    mipMapMode: 0",
		"    enableMipMap: 0",
		"    sRGBTexture: 1",
		"    linearTexture: 0",
		"    fadeOut: 0",
		"    borderMipMap: 0",
		"    mipMapsPreserveCoverage: 0",
		"    alphaTestReferenceValue: 0.5",
		"    mipMapFadeDistanceStart: 1",
		"    mipMapFadeDistanceEnd: 3",
		"  bumpmap:",
		"    convertToNormalMap: 0",
		"    externalNormalMap: 0",
		"    heightScale: 0.25",
		"    normalMapFilter: 0",
		"    flipGreenChannel: 0",
		"  isReadable: 0",
		"  streamingMipmaps: 0",
		"  streamingMipmapsPriority: 0",
		"  vTOnly: 0",
		"  ignoreMipmapLimit: 0",
		"  grayScaleToAlpha: 0",
		"  generateCubemap: 6",
		"  cubemapConvolution: 0",
		"  seamlessCubemap: 0",
		"  textureFormat: 1",
		"  maxTextureSize: 2048",
		"  textureSettings:",
		"    serializedVersion: 2",
		"    filterMode: 1",
		"    aniso: 1",
		"    mipBias: 0",
		"    wrapU: 1",
		"    wrapV: 1",
		"    wrapW: 0",
		"  nPOTScale: 0",
		"  lightmap: 0",
		"  compressionQuality: 50",
		"  spriteMode: 1",
		"  spriteExtrude: 1",
		"  spriteMeshType: 1",
		"  alignment: 9",
		"  spritePivot: {x: 0.5, y: 0}",
		"  spritePixelsToUnits: 100",
		"  spriteBorder: {x: 0, y: 0, z: 0, w: 0}",
		"  spriteGenerateFallbackPhysicsShape: 1",
		"  alphaUsage: 1",
		"  alphaIsTransparency: 1",
		"  spriteTessellationDetail: -1",
		"  textureType: 8",
		"  textureShape: 1",
		"  singleChannelComponent: 0",
		"  flipbookRows: 1",
		"  flipbookColumns: 1",
		"  maxTextureSizeSet: 0",
		"  compressionQualitySet: 0",
		"  textureFormatSet: 0",
		"  ignorePngGamma: 0",
		"  applyGammaDecoding: 0",
		"  swizzle: 50462976",
		"  cookieLightType: 0",
		"  platformSettings:",
		"  - serializedVersion: 3",
		"    buildTarget: DefaultTexturePlatform",
		"    maxTextureSize: 2048",
		"    resizeAlgorithm: 0",
		"    textureFormat: -1",
		"    textureCompression: 1",
		"    compressionQuality: 50",
		"    crunchedCompression: 0",
		"    allowsAlphaSplitting: 0",
		"    overridden: 0",
		"    ignorePlatformSupport: 0",
		"    androidETC2FallbackOverride: 0",
		"    forceMaximumCompressionQuality_BC6H_BC7: 0",
		"  - serializedVersion: 3",
		"    buildTarget: Standalone",
		"    maxTextureSize: 2048",
		"    resizeAlgorithm: 0",
		"    textureFormat: -1",
		"    textureCompression: 1",
		"    compressionQuality: 50",
		"    crunchedCompression: 0",
		"    allowsAlphaSplitting: 0",
		"    overridden: 0",
		"    ignorePlatformSupport: 0",
		"    androidETC2FallbackOverride: 0",
		"    forceMaximumCompressionQuality_BC6H_BC7: 0",
		"  - serializedVersion: 3",
		"    buildTarget: Android",
		"    maxTextureSize: 2048",
		"    resizeAlgorithm: 0",
		"    textureFormat: -1",
		"    textureCompression: 1",
		"    compressionQuality: 50",
		"    crunchedCompression: 0",
		"    allowsAlphaSplitting: 0",
		"    overridden: 0",
		"    ignorePlatformSupport: 0",
		"    androidETC2FallbackOverride: 0",
		"    forceMaximumCompressionQuality_BC6H_BC7: 0",
		"  spriteSheet:",
		"    serializedVersion: 2",
		"    sprites: []",
		"    outline: []",
		"    physicsShape: []",
		"    bones: []",
		"    spriteID: 5e97eb03825dee720800000000000000",
		"    internalID: 1537655665",
		"    vertices: []",
		"    indices: ",
		"    edges: []",
		"    weights: []",
		"    secondaryTextures: []",
		"    nameFileIdTable: {}",
		"  mipmapLimitGroupName: ",
		"  pSDRemoveMatte: 0",
		"  userData: ",
		"  assetBundleName: ",
		"  assetBundleVariant: ",
	];

	/** [textureTemplateLines] as one string, with LF endings. **/
	public static function textureTemplate():String
	{
		var sb = new StringBuf();
		for (line in textureTemplateLines)
		{
			sb.add(line);
			sb.add("\n");
		}
		return sb.toString();
	}

	// ------------------------------------------------------------- the importers

	/**
		A folder's `.meta`: `DefaultImporter` with `folderAsset: yes`.

		Unity writes one for every directory under `Assets/`, including the
		directories that hold nothing but other directories. Without it the folder
		is not part of the project's asset database, and the assets inside it are
		not indexed — which is why an export that creates directories writes these
		too.
	**/
	public static function forFolder(guid:String):MetaDocument
	{
		return MetaDocument.create(guid, "DefaultImporter", true);
	}

	/**
		A texture's `.meta`, sprite import settings included.

		[templatePath] names a `.meta` file to use as the template instead of the
		built in 2022.3 one — pass one from the project being written into when its
		Unity version or its import settings differ, which is the difference
		between a file Unity leaves alone and one it rewrites.

		[settings] are applied on top of the template, so a field the settings do
		not mention keeps whatever the template had.
	**/
	public static function forTexture(guid:String, ?settings:TextureImportSettings, ?templatePath:String):MetaDocument
	{
		var meta = templatePath == null ? MetaDocument.parse(textureTemplate()) : MetaDocument.fromFile(templatePath);
		if (meta == null) meta = MetaDocument.parse(textureTemplate());
		// A template of the wrong kind would silently take texture settings in a
		// section that means something else, so it is refused by name.
		if (meta.importer != "TextureImporter")
		{
			var source = templatePath == null ? "the built in template" : '"' + templatePath + '"';
			throw source + " is a " + meta.importer + " .meta, not a TextureImporter: a texture needs a texture template";
		}
		meta.guid = guid;
		var applied = settings == null ? new TextureImportSettings() : settings;
		applied.applyTo(meta);
		return meta;
	}

	/**
		A native asset's `.meta`: `NativeFormatImporter` plus the main object id.

		[mainObjectFileId] is the object references to this asset point at —
		`2100000` for a `.mat`, `11400000` for a `.asset`. It defaults to the
		material id because a generated `.mat` is what this library writes most;
		pass [AssetReference.mainObjectIdOf] for anything else.
	**/
	public static function forNativeAsset(guid:String, ?mainObjectFileId:Int64):MetaDocument
	{
		var meta = MetaDocument.create(guid, "NativeFormatImporter");
		meta.mainObjectFileId = mainObjectFileId == null ? Int64.ofInt(AssetReference.MATERIAL_ID) : mainObjectFileId;
		return meta;
	}

	/** A prefab's `.meta`: `PrefabImporter`. **/
	public static function forPrefab(guid:String):MetaDocument
	{
		return MetaDocument.create(guid, "PrefabImporter");
	}

	/**
		A C# script's `.meta`: `MonoImporter`.

		Field for field what a Unity 2022.3 project writes in a `.cs.meta`,
		including `icon: {instanceID: 0}` — a reference shaped differently from
		every other one in this library, which is exactly why it is written here
		rather than assembled by the caller.
	**/
	public static function forScript(guid:String):MetaDocument
	{
		var meta = MetaDocument.create(guid, "MonoImporter");
		var section = meta.section();
		section.set("serializedVersion", plain("2"));
		section.set("defaultReferences", new hxunity.yaml.YamlSeq());
		section.set("executionOrder", plain("0"));
		var icon = new hxunity.yaml.YamlMap(null, true);
		icon.set("instanceID", plain("0"));
		section.set("icon", icon);
		return meta;
	}

	// -------------------------------------------------------------- rewriting

	/**
		A copy of the `.meta` at [templatePath] with its GUID replaced.

		This is the path with the best chance of Unity leaving the file alone: every
		import setting, every field this library does not model, and the
		`serializedVersion` of the importer section all come from a file Unity
		wrote itself. Use it when a project has its own import settings; use the
		per importer factories when there is nothing to copy.
	**/
	public static function rewriteGuid(templatePath:String, guid:String):MetaDocument
	{
		var meta = MetaDocument.fromFile(templatePath);
		if (meta == null) throw 'cannot read the .meta template "$templatePath"';
		meta.guid = guid;
		return meta;
	}

	/** [rewriteGuid] for a template already in memory. **/
	public static function rewriteGuidText(templateText:String, guid:String):MetaDocument
	{
		var meta = MetaDocument.parse(templateText);
		meta.guid = guid;
		return meta;
	}

	static function plain(text:String):hxunity.yaml.YamlScalar
	{
		return new hxunity.yaml.YamlScalar(text, hxunity.yaml.ScalarKind.Plain);
	}
}
