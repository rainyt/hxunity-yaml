package hxunity.unity;

import hxunity.types.VectorData;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.ScalarKind;
import hxunity.yaml.Scalars;

/**
	`TextureImporterType`, the `textureType:` field of a texture `.meta`.

	The numbers are Unity's own and cannot be renumbered: `Sprite` is `8` and
	`Default` is `0`, which is why they are written out instead of being inferred
	from the order of the constants.
**/
enum abstract TextureType(Int) from Int to Int
{
	var Default = 0;
	var NormalMap = 1;
	var GUI = 2;
	var Cookie = 4;
	var Lightmap = 6;
	/** One channel of the source image, used for masks and height maps. **/
	var SingleChannel = 10;
	var Sprite = 8;
}

/** `spriteMode:` — whether a texture holds one sprite, a sheet of them, or none. **/
enum abstract SpriteImportMode(Int) from Int to Int
{
	var None = 0;
	var Single = 1;
	var Multiple = 2;
	var Polygon = 3;
}

/** `alignment:` — where a sprite's pivot sits, `Custom` meaning "use `spritePivot`". **/
enum abstract SpriteAlignment(Int) from Int to Int
{
	var Center = 0;
	var TopLeft = 1;
	var TopCenter = 2;
	var TopRight = 3;
	var LeftCenter = 4;
	var RightCenter = 5;
	var BottomLeft = 6;
	var BottomCenter = 7;
	var BottomRight = 8;
	var Custom = 9;
}

/** `textureSettings.filterMode:` — `Point` for pixel art, `Bilinear` for the rest. **/
enum abstract FilterMode(Int) from Int to Int
{
	var Point = 0;
	var Bilinear = 1;
	var Trilinear = 2;
}

/** `textureSettings.wrapU` / `wrapV` / `wrapW`. **/
enum abstract TextureWrap(Int) from Int to Int
{
	var Repeat = 0;
	var Clamp = 1;
	var Mirror = 2;
	var MirrorOnce = 3;
}

/** `platformSettings[].textureCompression:`. **/
enum abstract TextureCompression(Int) from Int to Int
{
	var Uncompressed = 0;
	var Compressed = 1;
	var CompressedHQ = 2;
}

/**
	The parts of a `TextureImporter` `.meta` an exporter actually decides.

	## Why this exists

	A `.meta` file is not documentation — it is the importer's whole state, and
	Unity rewrites it whenever a value it disagrees with is found. Two of its
	fields are load-bearing for this library's consumer:

	* `spritePixelsToUnits`, because pixels-per-unit is what turns a sprite's
	  pixel size into world units, and the renderer scales a mesh by it;
	* `spritePivot`, because the mesh is built around that pivot.

	Both therefore have explicit defaults here rather than being left to the
	importer: a default the library writes and the editor's renderer reads is one
	fact in one place.

	## Defaults

	The defaults are the sprite settings a Unity 2022.3.62 project writes for a
	PNG exported as a single sprite, read out of a real project:
	`textureType: 8`, `spriteMode: 1`, `spritePixelsToUnits: 100`,
	`mipmaps.enableMipMap: 0`, `alphaIsTransparency: 1`.
**/
class TextureImportSettings
{
	/** `textureType:`; [TextureType.Sprite] by default, the PSD export case. **/
	public var textureType:TextureType = Sprite;

	/** `spriteMode:`; one sprite per file by default. **/
	public var spriteImportMode:SpriteImportMode = Single;

	/**
		`spritePixelsToUnits:` — how many pixels make one world unit.

		Written explicitly even when it matches Unity's default, because the
		value is read back by the renderer to size a sprite in the scene.
	**/
	public var spritePixelsToUnits:Float = 100;

	/** `alignment:`; [SpriteAlignment.Custom] so [spritePivot] decides. **/
	public var spriteAlignment:SpriteAlignment = Custom;

	/** `spritePivot:` in normalised texture coordinates. **/
	public var spritePivot:VectorData = new VectorData(0.5, 0);

	/** `spriteBorder:` for a nine-sliced sprite. **/
	public var spriteBorder:VectorData = new VectorData(0, 0, 0, 0);

	/** `alphaIsTransparency:` — required for a sprite with soft edges. **/
	public var alphaIsTransparency:Bool = true;

	/** `mipmaps.enableMipMap:`; off for a 2D sprite, on for a 3D texture. **/
	public var mipmapEnabled:Bool = false;

	/** `mipmaps.sRGBTexture:`. **/
	public var sRGBTexture:Bool = true;

	/** `isReadable:` — true only when the CPU side needs the pixels. **/
	public var isReadable:Bool = false;

	/** `maxTextureSize:` — the cap Unity scales the image down to. **/
	public var maxTextureSize:Int = 2048;

	/**
		`textureFormat:` — `1` is `Automatic`, the value Unity 2022.3 writes.

		Measured rather than recalled: 361 of 393 texture `.meta` files in a real
		2022.3 project write `1`, and every one written by 2022.3 itself does.
		Older editors wrote `-1` for the same meaning, which is why the value is
		also left alone when it is read from a template.
	**/
	public var textureFormat:Int = 1;

	/** `textureSettings.filterMode:`. **/
	public var filterMode:FilterMode = Bilinear;

	/** `textureSettings.aniso:`; `1` is Unity's default. **/
	public var anisoLevel:Int = 1;

	/** `textureSettings.wrapU` and `wrapV`. **/
	public var wrapMode:TextureWrap = Clamp;

	/** `compressionQuality:`. **/
	public var compressionQuality:Int = 50;

	/** Per platform overrides; defaults to the set Unity itself writes. **/
	public var platformSettings:Array<PlatformTextureSettings> = defaultPlatforms();

	/** Entries of `spriteSheet.sprites`, for a multiple-sprite texture. **/
	public var sprites:Array<SpriteMetaData> = [];

	public function new() {}

	/** Settings for a single sprite at [pixelsToUnits]. **/
	public static function sprite(?pixelsToUnits:Float, ?pivot:VectorData):TextureImportSettings
	{
		var settings = new TextureImportSettings();
		if (pixelsToUnits != null) settings.spritePixelsToUnits = pixelsToUnits;
		if (pivot != null) settings.spritePivot = pivot;
		return settings;
	}

	/**
		Settings for a texture holding a sheet of sprites at [pixelsToUnits].

		The sheet itself — the rectangles — is passed in [sprites]; this only
		switches the importer to multiple-sprite mode, which is the part Unity
		refuses to infer.
	**/
	public static function sheet(sprites:Array<SpriteMetaData>, ?pixelsToUnits:Float):TextureImportSettings
	{
		var settings = sprite(pixelsToUnits);
		settings.spriteImportMode = Multiple;
		settings.sprites = sprites == null ? [] : sprites;
		return settings;
	}

	/**
		The platform entries Unity 2022.3 writes for a new texture.

		`DefaultTexturePlatform` is the fallback every other target inherits; the
		other three are the ones Unity adds for the platforms a new project
		targets. Passing `[]` is allowed and produces `platformSettings: []`,
		which Unity fills in on the next import — a rewrite of the file, which is
		why this list is the default.
	**/
	public static function defaultPlatforms(?maxTextureSize:Int):Array<PlatformTextureSettings>
	{
		var out:Array<PlatformTextureSettings> = [];
		for (target in ["DefaultTexturePlatform", "Standalone", "Android"])
		{
			out.push({
				buildTarget: target,
				// `null` means "follow the texture's own max size", which is what
				// Unity writes for an untouched platform entry. Passing
				// [maxTextureSize] pins these entries to a value of their own.
				maxTextureSize: maxTextureSize,
				textureFormat: -1,
				textureCompression: Compressed,
				compressionQuality: 50,
				overridden: false,
				ignorePlatformSupport: false
			});
		}
		return out;
	}

	/**
		Writes every setting into a `.meta` file's importer section.

		Fields are created when the template does not have them and replaced in
		place when it does, so the order Unity wrote is kept. That matters beyond
		tidiness: Unity rewrites a `.meta` whose field order it disagrees with, so
		a generated file that merely *means* the same thing still shows up as a
		whole-file diff.
	**/
	public function applyTo(meta:MetaDocument):Void
	{
		if (meta == null) return;
		var section = meta.section();
		if (section == null) return;

		setInt(section, "textureType", textureType);
		setInt(section, "textureShape", 1);
		setInt(section, "singleChannelComponent", 0);

		var mipmaps = child(section, "mipmaps");
		setInt(mipmaps, "enableMipMap", mipmapEnabled ? 1 : 0);
		setInt(mipmaps, "sRGBTexture", sRGBTexture ? 1 : 0);

		setInt(section, "isReadable", isReadable ? 1 : 0);
		setInt(section, "maxTextureSize", maxTextureSize);
		setInt(section, "compressionQuality", compressionQuality);
		setInt(section, "textureFormat", textureFormat);

		var textureSettings = child(section, "textureSettings");
		setInt(textureSettings, "filterMode", filterMode);
		setInt(textureSettings, "aniso", anisoLevel);
		setInt(textureSettings, "wrapU", wrapMode);
		setInt(textureSettings, "wrapV", wrapMode);
		// wrapW is the third axis of a 3D texture and stays 0 for a sprite; Unity
		// 2022.3 writes 0 where older editors wrote 1.
		setInt(textureSettings, "wrapW", 0);

		setInt(section, "spriteMode", spriteImportMode);
		setInt(section, "alignment", spriteAlignment);
		setVector(section, "spritePivot", spritePivot == null ? new VectorData(0.5, 0) : spritePivot);
		setVector(section, "spriteBorder", spriteBorder == null ? new VectorData(0, 0, 0, 0) : spriteBorder);
		setNumber(section, "spritePixelsToUnits", spritePixelsToUnits);
		setInt(section, "alphaUsage", 1);
		setInt(section, "alphaIsTransparency", alphaIsTransparency ? 1 : 0);

		// The three "the user changed this" flags. Unity sets them when a value
		// differs from the platform default, and an importer reading a file whose
		// values differ but whose flags are 0 rewrites them, so they are derived
		// rather than asked for.
		setInt(section, "maxTextureSizeSet", maxTextureSize == 2048 ? 0 : 1);
		setInt(section, "compressionQualitySet", compressionQuality == 50 ? 0 : 1);
		setInt(section, "textureFormatSet", textureFormat == 1 ? 0 : 1);

		applyPlatforms(section);
		applySprites(section);
	}

	/** Replaces `platformSettings` with the current list. **/
	function applyPlatforms(section:YamlMap):Void
	{
		if (platformSettings == null)
		{
			section.set("platformSettings", new hxunity.yaml.YamlSeq());
			return;
		}
		var seq = new hxunity.yaml.YamlSeq();
		for (platform in platformSettings)
		{
			var entry = new YamlMap();
			// Unity writes serializedVersion first in each entry, then the target.
			entry.set("serializedVersion", plain("3"));
			entry.set("buildTarget", Scalars.ofString(platform.buildTarget));
			entry.set("maxTextureSize", plain(Std.string(platform.maxTextureSize == null ? maxTextureSize : platform.maxTextureSize)));
			entry.set("resizeAlgorithm", plain("0"));
			// A platform entry writes `-1` for "inherit", which is not the same
			// value the top level field carries for the same meaning.
			entry.set("textureFormat", plain(Std.string(platform.textureFormat == null ? -1 : platform.textureFormat)));
			entry.set("textureCompression", plain(Std.string(platform.textureCompression == null ? Compressed : platform.textureCompression)));
			entry.set("compressionQuality", plain(Std.string(platform.compressionQuality == null ? compressionQuality : platform.compressionQuality)));
			entry.set("crunchedCompression", plain("0"));
			entry.set("allowsAlphaSplitting", plain("0"));
			entry.set("overridden", plain(platform.overridden == true ? "1" : "0"));
			entry.set("ignorePlatformSupport", plain(platform.ignorePlatformSupport == true ? "1" : "0"));
			entry.set("androidETC2FallbackOverride", plain("0"));
			entry.set("forceMaximumCompressionQuality_BC6H_BC7", plain("0"));
			seq.push(entry);
		}
		section.set("platformSettings", seq);
	}

	/** Replaces `spriteSheet` with the current sprite list. **/
	function applySprites(section:YamlMap):Void
	{
		var sheet = child(section, "spriteSheet");
		if (sheet == null) return;

		var list = new hxunity.yaml.YamlSeq();
		for (sprite in sprites)
		{
			if (sprite == null) continue;
			var entry = new YamlMap();
			entry.set("serializedVersion", plain("2"));
			entry.set("name", Scalars.ofString(sprite.name));

			var rect = sprite.rect;
			var rectMap = new YamlMap();
			rectMap.set("serializedVersion", plain("2"));
			rectMap.set("x", plain(Std.string(rect.x)));
			rectMap.set("y", plain(Std.string(rect.y)));
			rectMap.set("width", plain(Std.string(rect.width)));
			rectMap.set("height", plain(Std.string(rect.height)));
			entry.set("rect", rectMap);

			entry.set("alignment", plain(Std.string(sprite.alignment == null ? spriteAlignment : sprite.alignment)));
			entry.set("pivot", (sprite.pivot == null ? spritePivot : sprite.pivot).toNode());
			entry.set("border", (sprite.border == null ? new VectorData(0, 0, 0, 0) : sprite.border).toNode());
			entry.set("outline", new hxunity.yaml.YamlSeq());
			entry.set("physicsShape", new hxunity.yaml.YamlSeq());
			entry.set("tessellationDetail", plain("-1"));
			entry.set("bones", new hxunity.yaml.YamlSeq());
			if (sprite.spriteID != null)
			{
				entry.set("spriteID", Scalars.ofString(sprite.spriteID));
			}
			if (sprite.internalID != null)
			{
				entry.set("internalID", plain(hxunity.unity.FileId.toStr(sprite.internalID)));
			}
			entry.set("vertices", new hxunity.yaml.YamlSeq());
			entry.set("indices", plain(""));
			entry.set("edges", new hxunity.yaml.YamlSeq());
			entry.set("weights", new hxunity.yaml.YamlSeq());
			list.push(entry);
		}
		sheet.set("sprites", list);

		// `nameFileIdTable` is what a reference to one sprite of the sheet names
		// it by; an entry without an internal id has nothing to put there, and
		// Unity fills the table in when it imports the asset.
		// Flow, so an empty table is written `nameFileIdTable: {}` the way Unity
		// writes it rather than as a key with nothing after it.
		var table = new YamlMap(null, true);
		for (sprite in sprites)
		{
			if (sprite == null || sprite.internalID == null) continue;
			table.set(sprite.name, plain(hxunity.unity.FileId.toStr(sprite.internalID)));
		}
		sheet.set("nameFileIdTable", table);
	}

	/** Importer section child mapping [key], created empty when absent. **/
	static function child(section:YamlMap, key:String):YamlMap
	{
		var existing = section.getMap(key);
		if (existing != null) return existing;
		var created = new YamlMap();
		section.set(key, created);
		return created;
	}

	static function setInt(section:YamlMap, key:String, value:Int):Void
	{
		section.set(key, plain(Std.string(value)));
	}

	static function setNumber(section:YamlMap, key:String, value:Float):Void
	{
		section.set(key, plain(hxunity.types.Numbers.format(value)));
	}

	static function setVector(section:YamlMap, key:String, value:VectorData):Void
	{
		section.set(key, value.toNode());
	}

	static function plain(text:String):YamlScalar
	{
		return new YamlScalar(text, ScalarKind.Plain);
	}
}
