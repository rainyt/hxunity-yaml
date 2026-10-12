package hxunity.unity;

/**
	The per platform override block of a `TextureImporter` `.meta`:

	```yaml
	  platformSettings:
	  - serializedVersion: 3
	    buildTarget: DefaultTexturePlatform
	    maxTextureSize: 2048
	    resizeAlgorithm: 0
	    textureFormat: -1
	    textureCompression: 1
	    compressionQuality: 50
	    crunchedCompression: 0
	    allowsAlphaSplitting: 0
	    overridden: 0
	    ignorePlatformSupport: 0
	    androidETC2FallbackOverride: 0
	    forceMaximumCompressionQuality_BC6H_BC7: 0
	```

	Unity writes one entry per build target the texture is imported for, and
	re-creates the missing ones the next time the asset is imported — which shows
	up as a rewrite of the `.meta` file. [TextureImportSettings.defaultPlatforms]
	produces the set a real Unity 2022.3 project writes, so an exported texture is
	not immediately rewritten on first import.

	`serializedVersion: 3` is what Unity 2022.3 writes in each entry; a `.meta`
	written by an older editor carries `2` there, which is another reason a
	generated file starts from a real template rather than from scratch.
**/
typedef PlatformTextureSettings = {
	/** Build target name, e.g. `DefaultTexturePlatform`, `Standalone`, `Android`. **/
	var buildTarget:String;

	/** Max texture size on this platform. **/
	var ?maxTextureSize:Int;

	/** `-1` for automatic, otherwise a `TextureImporterFormat` value. **/
	var ?textureFormat:Int;

	/** `0` uncompressed, `1` normal, `2` high quality. **/
	var ?textureCompression:Int;

	/** Compression quality, `0` to `100`. **/
	var ?compressionQuality:Int;

	/** True when the platform's settings were explicitly overridden. **/
	var ?overridden:Bool;

	/** True when Unity decides the platform's settings, ignoring the overrides above. **/
	var ?ignorePlatformSupport:Bool;
}
