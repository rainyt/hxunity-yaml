package;

import haxe.Int64;
import hxunity.prefab.UnityPrefab;
import hxunity.types.ColorData;
import hxunity.types.VectorData;
import hxunity.unity.AssetClassifier;
import hxunity.unity.AssetGuid;
import hxunity.unity.AssetGuidIndex;
import hxunity.unity.AssetReference;
import hxunity.unity.AssetWriter;
import hxunity.unity.CachedGuidIndex;
import hxunity.unity.MaterialProperties;
import hxunity.unity.MetaDocument;
import hxunity.unity.MetaFile;
import hxunity.unity.MetaWriter;
import hxunity.unity.TextureImportSettings;
import hxunity.unity.UnityAssetFactory;
import hxunity.unity.UnityMaterial;
import hxunity.unity.UnityReference;
import hxunity.yaml.ClassIds;
import hxunity.yaml.UnityYamlDocument;
import hxunity.yaml.YamlMap;

/**
	Tests for the writing side: GUIDs, `.meta` files, materials, component
	templates and the asset factory.

	The fixtures in `tests/fixtures/Unity2022/` are files a real Unity 2022.3.62
	project wrote, kept as the reference for what this side has to produce. Where
	a generated file and a fixture describe the same asset the test compares them
	**byte for byte** — that is the closest this suite can get to the acceptance
	test the requirements ask for (import the generated asset in Unity and check
	that `git diff` is empty), and it catches the same mistakes: a missing field,
	a field in the wrong place, a trailing space that is not there.
**/
class TestAuthoring
{
	/** Real Unity 2022.3.62 files, see `tests/fixtures/README.md`. **/
	static inline var FIXTURES = "tests/fixtures/Unity2022";

	/** Scratch directory for files this suite writes. **/
	static inline var SCRATCH = "build/test-authoring";

	public static function run():Void
	{
		var only = Sys.getEnv("HXU_ONLY");
		if (only != null && only.length > 0)
		{
			switch (only)
			{
				case "guids": guids();
				case "metas": metas();
				case "material": material();
				case "prefab": prefab();
				case "fields": fields();
				case "references": references();
				case "index": index();
				case "writer": writer();
				case "factory": factory();
				default: Sys.println("unknown sub test " + only);
			}
			return;
		}
		guids();
		metas();
		material();
		prefab();
		fields();
		references();
		index();
		writer();
		factory();
	}

	/** Prints a progress marker so a hang points at the sub test. **/
	static function step(name:String):Void
	{
		TestMain.note("    step: " + name);
	}

	static function fixture(name:String):String
	{
		return FIXTURES + "/" + name;
	}

	static function read(path:String):String
	{
		return sys.io.File.getContent(path);
	}

	/**
		Compares generated text against a fixture, ignoring the line ending used.

		The fixtures are checked out with the platform's line endings (the
		repository sets `* text=auto`), so on Windows they arrive as CRLF while
		what this library generates is always LF. Everything else has to match
		exactly — that the generated file uses LF, UTF-8 and one trailing newline
		is asserted separately, in the writer group.
	**/
	static function sameLines(actual:String, expected:String, message:String):Void
	{
		Assert.stringEquals(withoutCr(actual), withoutCr(expected), message);
	}

	static function withoutCr(text:String):String
	{
		return text == null ? null : text.split("\r\n").join("\n").split("\r").join("\n");
	}

	/** The field names of a document's body, in order. **/
	static function fieldNames(document:UnityYamlDocument):Array<String>
	{
		var out = [];
		if (document == null || !Std.isOfType(document.body, YamlMap)) return out;
		var body:YamlMap = cast document.body;
		if (body.entries.length == 0) return out;
		var inner = body.entries[0].value;
		if (inner == null || !Std.isOfType(inner, YamlMap)) return out;
		for (entry in (cast inner : YamlMap).entries)
		{
			out.push(entry.key);
		}
		return out;
	}

	/** Every document of [path] whose class name is [className], in file order. **/
	static function documentsNamed(prefab:UnityPrefab, className:String):Array<UnityYamlDocument>
	{
		var out = [];
		for (document in prefab.documents.documents)
		{
			if (document.bodyName == className) out.push(document);
		}
		return out;
	}

	// ------------------------------------------------------------------- guids

	static function guids():Void
	{
		Assert.test("Authoring.guids");
		step("format");
		var sample = AssetGuid.generate();
		Assert.equals(sample.length, AssetGuid.LENGTH, "a generated GUID is 32 characters");
		Assert.isTrue(AssetGuid.isValid(sample), "a generated GUID is valid");
		Assert.stringEquals(sample, sample.toLowerCase(), "a generated GUID is lowercase");
		Assert.isTrue(AssetGuid.isUsable(sample), "a generated GUID names a project asset");

		Assert.isTrue(AssetGuid.isValid("9e613c018e232044db897e24a5e4fd3f"), "a real GUID is valid");
		Assert.isTrue(AssetGuid.isValid("9E613C018E232044DB897E24A5E4FD3F"), "an upper case GUID is still valid");
		Assert.isFalse(AssetGuid.isValid("9e613c018e232044db897e24a5e4fd3"), "a 31 character GUID is not valid");
		Assert.isFalse(AssetGuid.isValid("9e613c018e232044db897e24a5e4fd3g"), "a non hex GUID is not valid");
		Assert.isFalse(AssetGuid.isValid(null), "null is not a GUID");
		Assert.stringEquals(AssetGuid.normalise(" 9E613C018E232044DB897E24A5E4FD3F "), "9e613c018e232044db897e24a5e4fd3f",
			"normalise trims and lowercases");
		Assert.isNull(AssetGuid.normalise(null), "normalise keeps null");

		step("reserved values");
		Assert.isTrue(AssetGuid.isNone(AssetGuid.NONE), "the all zero GUID is the none GUID");
		Assert.isTrue(AssetGuid.isNone("0000"), "a shorter spelling of zero is none too");
		Assert.isFalse(AssetGuid.isNone("0000000000000000e000000000000000"), "Unity's built in GUID is not the zero one");
		Assert.isFalse(AssetGuid.isNone(sample), "a generated GUID is not none");
		Assert.isTrue(AssetGuid.isBuiltin("0000000000000000f000000000000000"), "Unity's built in GUID is recognised");
		Assert.isFalse(AssetGuid.isUsable("0000000000000000f000000000000000"), "a built in GUID is not usable");
		Assert.isFalse(AssetGuid.isUsable(AssetGuid.NONE), "the none GUID is not usable");

		step("uniqueness over 100000 draws");
		// The size the requirement asks for: a batch export mints a few hundred
		// GUIDs, and the guarantee has to hold well past that.
		var seen = new Map<String, Bool>();
		var collisions = 0;
		var invalid = 0;
		var reserved = 0;
		for (i in 0...100000)
		{
			var guid = AssetGuid.generate();
			if (seen.exists(guid)) collisions++;
			seen.set(guid, true);
			if (!AssetGuid.isValid(guid)) invalid++;
			if (AssetGuid.isNone(guid) || AssetGuid.isBuiltin(guid)) reserved++;
		}
		Assert.equals(collisions, 0, "100,000 generated GUIDs hold no duplicate");
		Assert.equals(invalid, 0, "100,000 generated GUIDs are all 32 hex digits");
		Assert.equals(reserved, 0, "100,000 generated GUIDs avoid the zero and built in GUIDs");
		var distinct = 0;
		for (key in seen.keys())
		{
			distinct++;
		}
		Assert.equals(distinct, 100000, "all 100,000 are distinct entries");

		step("generateUnique");
		var taken = new Map<String, Bool>();
		var first = AssetGuid.generateUnique(function(guid) return taken.exists(guid));
		taken.set(first, true);
		var second = AssetGuid.generateUnique(function(guid) return taken.exists(guid));
		Assert.isFalse(first == second, "generateUnique avoids a taken GUID");
		Assert.isTrue(AssetGuid.isUsable(second), "generateUnique still returns a usable GUID");

		step("allocation through an index");
		var index = new AssetGuidIndex("/nonexistent-project");
		var allocated = new Map<String, Bool>();
		for (i in 0...200)
		{
			var guid = index.newGuid();
			Assert.isFalse(allocated.exists(guid), "newGuid does not repeat itself");
			allocated.set(guid, true);
		}
		Assert.equals(index.size(), 0, "allocating GUIDs does not add assets to the index");
	}

	// ------------------------------------------------------------------- metas

	static function metas():Void
	{
		Assert.test("Authoring.metas");

		step("folder .meta matches Unity byte for byte");
		var folder = MetaWriter.forFolder("9e613c018e232044db897e24a5e4fd3f");
		sameLines(folder.emit(), read(fixture("Folder/Art.meta")), "a generated folder .meta is what Unity wrote");
		var parsed = MetaFile.parse(folder.emit());
		Assert.equals(parsed.guid, "9e613c018e232044db897e24a5e4fd3f", "the generated folder .meta carries its GUID");
		Assert.isTrue(parsed.isFolder, "the generated folder .meta is a folder asset");
		Assert.equals(parsed.importer, "DefaultImporter", "the generated folder .meta uses DefaultImporter");

		step("native asset .meta matches Unity byte for byte");
		var native = MetaWriter.forNativeAsset("6eb88238706c38746bb3e2a2be435be3");
		sameLines(native.emit(), read(fixture("Materials/plane.mat.meta")), "a generated .mat .meta is what Unity wrote");

		step("prefab .meta matches Unity byte for byte");
		var prefabMeta = MetaWriter.forPrefab("1acaba0080b3e534dbfe189182ef85db");
		sameLines(prefabMeta.emit(), read(fixture("Prefabs/damGrp_8_s.prefab.meta")), "a generated prefab .meta is what Unity wrote");

		step("script .meta matches Unity's field set");
		var script = MetaWriter.forScript("8b8751c7c8fe18d4181abdb270889f31").emit();
		Assert.contains(script, "  icon: {instanceID: 0}\n", "a generated .cs .meta writes Unity's instanceID shaped icon");
		Assert.contains(script, "MonoImporter:\n", "a generated .cs .meta uses MonoImporter");

		step("texture .meta matches Unity byte for byte");
		var settings = TextureImportSettings.sprite(100, new VectorData(0.5, 0));
		var texture = MetaWriter.forTexture("b5b59a04266677f4db30660c10721917", settings);
		sameLines(texture.emit(), read(fixture("Textures/hand.png.meta")), "a generated texture .meta is what Unity wrote");
		Assert.equals(texture.getString("spritePixelsToUnits"), "100", "the pixels per unit the settings asked for is written");
		Assert.equals(texture.getString("textureType"), "8", "the texture is imported as a sprite");
		Assert.equals(texture.getString("spriteMode"), "1", "the texture holds a single sprite");
		Assert.equals(texture.getString("serializedVersion"), "13", "the importer declares the version Unity 2022.3 writes");

		step("texture settings are applied");
		var other = TextureImportSettings.sprite(16, new VectorData(0.5, 0.25));
		other.mipmapEnabled = true;
		other.alphaIsTransparency = false;
		other.maxTextureSize = 512;
		other.filterMode = hxunity.unity.TextureImportSettings.FilterMode.Point;
		other.wrapMode = hxunity.unity.TextureImportSettings.TextureWrap.Repeat;
		var changed = MetaWriter.forTexture("11111111111111111111111111111111", other);
		Assert.equals(changed.getString("spritePixelsToUnits"), "16", "a custom PPU is written");
		Assert.equals(changed.getStringPath("spritePivot.y"), "0.25", "a custom pivot is written");
		Assert.equals(changed.getStringPath("mipmaps.enableMipMap"), "1", "mipmaps can be switched on");
		Assert.equals(changed.getString("alphaIsTransparency"), "0", "alpha transparency can be switched off");
		Assert.equals(changed.getString("maxTextureSize"), "512", "a custom max size is written");
		Assert.equals(changed.getString("maxTextureSizeSet"), "1", "changing the max size sets Unity's flag for it");
		Assert.equals(changed.getStringPath("textureSettings.filterMode"), "0", "the filter mode is written");
		Assert.equals(changed.getStringPath("textureSettings.wrapU"), "0", "the wrap mode is written");
		// The platform entries follow the top level size, or Unity rewrites them.
		Assert.contains(changed.emit(), "    maxTextureSize: 512\n", "the platform entries follow the max size");
		Assert.equals(changed.guid, "11111111111111111111111111111111", "the GUID is the one that was asked for");

		step("sprite sheet entries");
		var sheet = TextureImportSettings.sheet([
			{
				name: "hand_0",
				rect: {x: 0, y: 64, width: 64, height: 64},
				pivot: new VectorData(0.5, 0.5),
				internalID: Int64.parseString("7242008812290275033")
			},
			{name: "hand_1", rect: {x: 64, y: 64, width: 64, height: 64}}
		], 100);
		var sheetMeta = MetaWriter.forTexture("22222222222222222222222222222222", sheet);
		Assert.equals(sheetMeta.getString("spriteMode"), "2", "a sheet is imported as multiple sprites");
		var sprites = sheetMeta.getPath("spriteSheet.sprites").asSeq();
		Assert.equals(sprites.length(), 2, "both sprites are written");
		Assert.equals(sprites.get(0).asMap().getString("name"), "hand_0", "a sprite keeps its name");
		Assert.equals(sprites.get(0).asMap().getMap("rect").getString("height"), "64", "a sprite keeps its rectangle");
		Assert.equals(sprites.get(0).asMap().getString("internalID"), "7242008812290275033", "a supplied internal id is written");
		Assert.isNull(sprites.get(1).asMap().get("internalID"), "a sprite without an internal id stays without one");
		Assert.equals(sheetMeta.getPath("spriteSheet.nameFileIdTable").asMap().getString("hand_0"), "7242008812290275033",
			"the name table maps a sprite to its internal id");

		step("rewriting a template only changes the GUID");
		var template = MetaDocument.parse(read(fixture("Textures/hand.png.meta")));
		var before = template.guid;
		var rewritten = MetaWriter.rewriteGuidText(read(fixture("Textures/hand.png.meta")), "33333333333333333333333333333333");
		Assert.equals(before, "b5b59a04266677f4db30660c10721917", "the template's own GUID is read");
		var lines = rewritten.emit().split("\n");
		var originalLines = read(fixture("Textures/hand.png.meta")).split("\n");
		Assert.equals(lines.length, originalLines.length, "rewriting a GUID does not change the line count");
		var differences = 0;
		for (i in 0...lines.length)
		{
			if (lines[i] != originalLines[i]) differences++;
		}
		Assert.equals(differences, 1, "rewriting a GUID changes exactly one line");
		Assert.stringEquals(lines[1], "guid: 33333333333333333333333333333333", "and that line is the GUID");

		step("a .meta read and written back is unchanged");
		for (name in [
			"Folder/Art.meta", "Materials/plane.mat.meta", "Prefabs/damGrp_8_s.prefab.meta", "Textures/hand.png.meta",
			"Textures/EmojiOne.png.meta"
		])
		{
			var text = read(fixture(name));
			Assert.stringEquals(MetaDocument.parse(text).emit(), text, '$name round trips through the model unchanged');
		}

		step("a texture cannot be built from the wrong template");
		Assert.throws(function() MetaWriter.forTexture("55555555555555555555555555555555", null, fixture("Folder/Art.meta")),
			"a folder .meta is refused as a texture template");

		step("a .meta without a GUID is refused");
		var caught = Assert.throws(function() MetaWriter.forFolder(null), "a missing GUID throws");
		Assert.contains(Std.string(caught), "GUID", "and says what is missing");

		step("a template of another vintage keeps its own fields");
		var old = MetaWriter.forTexture("44444444444444444444444444444444", TextureImportSettings.sprite(100), fixture("Textures/EmojiOne.png.meta"));
		Assert.equals(old.getString("serializedVersion"), "5", "an older template keeps its importer version");
		Assert.contains(old.emit(), "fileIDToRecycleName:", "an older template keeps the fields this library does not model");
		Assert.equals(old.getString("spritePixelsToUnits"), "100", "settings still override the template");
	}

	// ---------------------------------------------------------------- material

	static function material():Void
	{
		Assert.test("Authoring.material");
		deleteTree(SCRATCH + "/Materials");

		step("a generated material has Unity's field set");
		var generated = UnityMaterial.create("5e21b1ce6d8f1b8478a1b1e1b1b1b1b1", "hand");
		var generatedNames = fieldNames(generated.document);
		var corpus = UnityPrefab.fromFile(fixture("Materials/plane.mat"));
		var corpusNames = fieldNames(corpus.firstDocumentOfClass(ClassIds.Material));
		Assert.stringEquals(generatedNames.join(","), corpusNames.join(","), "a generated material writes Unity's fields in Unity's order");
		Assert.equals(generated.document.fileIdText(), "2100000", "the Material object has the file id references use");
		Assert.equals(generated.object().getString("serializedVersion"), "8", "the material declares serializedVersion 8");
		Assert.equals(generated.renderQueue(), -1, "the render queue is left to the shader");
		Assert.isTrue(generatedNames.indexOf("m_SavedProperties") >= 0, "the properties block is present");

		step("properties round trip");
		var value = new ColorData(0.25, 0.5, 0.75, 1);
		generated.setColor("_Color", value);
		generated.setFloat("_Cutoff", 0.5);
		generated.setVector("_Pivot", new VectorData(0.5, 0.25));
		generated.setTexture("_MainTex", "cfc2b0892ed1aad4aa81b3907ed45b22");
		Assert.stringEquals(generated.getColor("_Color").toHex(), value.toHex(), "a colour reads back");
		Assert.equals(generated.properties().getFloat("_Cutoff"), 0.5, "a float reads back");
		var pivot = generated.getVector("_Pivot");
		Assert.equals(pivot.x, 0.5, "a vector's first component reads back");
		Assert.equals(pivot.y, 0.25, "a vector's second component reads back");
		Assert.isFalse(pivot.hasZ, "a two component vector stays two components wide");
		Assert.stringEquals(generated.getTexture("_MainTex"), "cfc2b0892ed1aad4aa81b3907ed45b22", "a texture reads back");
		Assert.contains(generated.emit(), "    - _Pivot: {r: 0.5, g: 0.25}\n", "a vector is written as r and g the way Unity writes one");
		Assert.contains(generated.emit(), "        m_Texture: {fileID: 2800000, guid: cfc2b0892ed1aad4aa81b3907ed45b22, type: 3}",
			"a texture reference carries the file id and type Unity writes");

		step("entries stay sorted the way Unity keeps them");
		var names = generated.properties().colorProperties();
		Assert.stringEquals(names.join(","), "_Color,_Pivot", "colour properties are ordered by name");
		generated.setColor("_AlphaColor", new ColorData(1, 1, 1, 1));
		Assert.stringEquals(generated.properties().colorProperties().join(","), "_AlphaColor,_Color,_Pivot",
			"a new property is inserted in order, not appended");

		step("removing a property");
		Assert.equals(generated.removeProperty("_Pivot"), "m_Colors", "removing reports which list held the property");
		Assert.isNull(generated.getVector("_Pivot"), "the property is gone");
		Assert.isNull(generated.removeProperty("_Pivot"), "removing it twice does nothing");

		step("reading the material a real project wrote");
		var real = UnityMaterial.fromFile(fixture("Materials/loading_Material.mat"));
		var properties = MaterialProperties.of(real.object());
		Assert.notNull(properties, "the properties of a parsed material are reachable");
		Assert.isTrue(properties.textureProperties().indexOf("_MainTex") >= 0, "its texture properties are listed");
		Assert.isNull(MaterialProperties.of(null), "and a null object has none");
		var guid = real.getTexture("_MainTex");
		Assert.equals(guid, "cfc2b0892ed1aad4aa81b3907ed45b22", "the texture of Unity's own material is read");
		Assert.isNull(real.getTexture("_BumpMap"), "a built in texture reference reads as no texture");
		Assert.notNull(real.shader(), "the shader reference is read");

		step("a material read and written back is unchanged");
		Assert.stringEquals(real.emit(), read(fixture("Materials/loading_Material.mat")), "a real material round trips unchanged");
		var plane = UnityMaterial.fromFile(fixture("Materials/plane.mat"));
		Assert.stringEquals(plane.emit(), read(fixture("Materials/plane.mat")), "a material with several documents round trips unchanged");

		step("editing Unity's own material changes one line");
		var before = read(fixture("Materials/plane.mat")).split("\n");
		plane.setColor("_Color", new ColorData(1, 0, 0, 1));
		var after = plane.emit().split("\n");
		Assert.equals(before.length, after.length, "editing a value does not change the line count");
		var changed = 0;
		for (i in 0...before.length)
		{
			if (before[i] != after[i]) changed++;
		}
		Assert.equals(changed, 1, "editing a colour changes exactly one line");

		step("saving and reading back");
		var target = SCRATCH + "/Materials/hand.mat";
		generated.save(target);
		Assert.isTrue(sys.FileSystem.exists(target), "the material file is written");
		var reloaded = UnityMaterial.fromFile(target);
		Assert.stringEquals(reloaded.getTexture("_MainTex"), "cfc2b0892ed1aad4aa81b3907ed45b22", "the written material reads back");
		Assert.equals(reloaded.name(), "hand", "the written material keeps its name");
		Assert.isFalse(sys.FileSystem.exists(target + ".tmp"), "no temporary file is left behind");
	}

	// ------------------------------------------------------------------ prefab

	static function prefab():Void
	{
		Assert.test("Authoring.prefab");
		deleteTree(SCRATCH + "/Prefabs");

		step("components are created with Unity's fields");
		var reference = UnityPrefab.fromFile(fixture("Prefabs/damGrp_8_s.prefab"));
		var prefab = UnityPrefab.createEmpty();
		var root = prefab.createGameObject("hand");
		var sorting = root.addComponent("SortingGroup");
		var filter = root.addComponent("MeshFilter");
		var renderer = root.addComponent("MeshRenderer");
		renderer.setSeq("m_Materials", [UnityReference.material("a97c105638bdf8b4a8650670310a4cd3").toNode()]);

		var referenceObjects = documentsNamed(reference, "GameObject");
		var generatedObjects = documentsNamed(prefab, "GameObject");
		Assert.equals(generatedObjects.length, 1, "the prefab holds one GameObject");
		Assert.stringEquals(fieldNames(generatedObjects[0]).join(","), fieldNames(referenceObjects[0]).join(","),
			"a created GameObject writes Unity's fields in Unity's order");
		Assert.stringEquals(fieldNames(documentsNamed(prefab, "Transform")[0]).join(","),
			fieldNames(documentsNamed(reference, "Transform")[0]).join(","), "a created Transform writes Unity's fields in Unity's order");
		Assert.stringEquals(fieldNames(documentsNamed(prefab, "SortingGroup")[0]).join(","),
			fieldNames(documentsNamed(reference, "SortingGroup")[0]).join(","), "a created SortingGroup writes Unity's fields in Unity's order");
		Assert.stringEquals(fieldNames(documentsNamed(prefab, "MeshFilter")[0]).join(","),
			fieldNames(documentsNamed(reference, "MeshFilter")[0]).join(","), "a created MeshFilter writes Unity's fields in Unity's order");
		Assert.stringEquals(fieldNames(documentsNamed(prefab, "MeshRenderer")[0]).join(","),
			fieldNames(documentsNamed(reference, "MeshRenderer")[0]).join(","),
			"a created MeshRenderer writes Unity's fields in Unity's order");
		Assert.notNull(renderer.getSeq("m_Materials"), "the created MeshRenderer has m_Materials");
		Assert.equals(renderer.getSeq("m_Materials").length(), 1, "and it holds the material that was assigned");
		Assert.notNull(sorting.getInt("m_SortingOrder"), "the created SortingGroup has m_SortingOrder");
		Assert.equals(renderer.getInt("m_SortingOrder"), 0, "the created MeshRenderer has m_SortingOrder");
		Assert.notNull(renderer.getInt("m_SortingLayerID"), "the created MeshRenderer has m_SortingLayerID");

		step("template fields are not injected into parsed objects");
		// The whole round trip guarantee: reading a real prefab and writing it
		// back has to be byte identical, which it would not be if a template
		// added a field to an object that came from a file.
		Assert.stringEquals(reference.emit(), read(fixture("Prefabs/damGrp_8_s.prefab")),
			"a real prefab round trips unchanged with templates in place");

		step("a second transform is refused");
		Assert.throws(function() root.addComponent("RectTransform"), "a GameObject cannot gain a second transform");

		step("a RectTransform can be created");
		var ui = prefab.createGameObject("panel", null, null, true);
		var rect = ui.transform();
		Assert.equals(rect.classId(), ClassIds.RectTransform, "the object has a RectTransform");
		Assert.notNull(rect.get("m_AnchorMin"), "the RectTransform has anchor fields");
		Assert.notNull(rect.get("m_SizeDelta"), "the RectTransform has a size");
		Assert.isNull(rect.get("serializedVersion"), "a RectTransform writes no serializedVersion, as Unity does not");

		step("the written prefab reads back with its material");
		var target = SCRATCH + "/Prefabs/hand.prefab";
		AssetWriter.ensureDirectory(SCRATCH + "/Prefabs");
		prefab.save(target);
		var reloaded = UnityPrefab.fromFile(target);
		var object = reloaded.find("hand");
		Assert.notNull(object, "the written prefab has its root object");
		var reloadedRenderer = object.getComponent(ClassIds.MeshRenderer);
		Assert.notNull(reloadedRenderer, "the written prefab has its MeshRenderer");
		var materials = reloadedRenderer.getSeq("m_Materials");
		Assert.notNull(materials, "the MeshRenderer still has m_Materials");
		Assert.stringEquals(UnityReference.fromNode(materials.get(0)).guid, "a97c105638bdf8b4a8650670310a4cd3",
			"the material reference survives the round trip");
		Assert.equals(UnityReference.fromNode(materials.get(0)).type, UnityReference.TYPE_NATIVE,
			"and it keeps the type Unity writes for a material");
	}

	// ------------------------------------------------------------------ fields

	static function fields():Void
	{
		Assert.test("Authoring.fields");

		var prefab = UnityPrefab.createEmpty();
		var object = prefab.createGameObject("fields");
		var component = object.addComponent("MeshRenderer");

		step("scalars");
		component.setInt("m_SortingOrder", -6);
		component.setFloat("m_ScaleInLightmap", 0.5);
		component.setBool("m_CastShadows", false);
		component.setString("m_Name", "yes: not a keyword");
		Assert.equals(component.getInt("m_SortingOrder"), -6, "an int reads back");
		Assert.equals(component.getFloat("m_ScaleInLightmap"), 0.5, "a float reads back");
		Assert.equals(component.getBool("m_CastShadows"), false, "a bool reads back as Unity's 0");
		Assert.stringEquals(component.getString("m_Name"), "yes: not a keyword", "a string reads back");
		Assert.contains(component.get("m_Name").toString(), "yes: not a keyword", "and is the text that was set");
		// A value that would not survive a plain round trip is quoted by the
		// writer, which is what `ofString` decides.
		var emitted = prefab.emit();
		Assert.contains(emitted, "m_Name: 'yes: not a keyword'", "a string that needs quoting gets quotes");
		Assert.contains(emitted, "m_CastShadows: 0", "a false bool is written as 0");
		Assert.contains(emitted, "m_SortingOrder: -6", "a negative int keeps its sign");

		step("value types");
		component.setVector("m_Size", new VectorData(1, 2, 3));
		component.setColor("m_Color", new ColorData(1, 0.5, 0, 1));
		component.setQuaternion("m_LocalRotation", new hxunity.types.QuaternionData(0, 0, 0, 1));
		var vector = VectorData.fromField(component.fields(), "m_Size");
		Assert.equals(vector.z, 3, "a vector reads back with all three components");
		Assert.stringEquals(ColorData.fromField(component.fields(), "m_Color").toHex(), "#FF8000FF", "a colour reads back");
		Assert.notNull(hxunity.types.QuaternionData.fromField(component.fields(), "m_LocalRotation"), "a rotation reads back");
		Assert.contains(prefab.emit(), "m_Size: {x: 1, y: 2, z: 3}", "a vector is written as a flow mapping");

		step("references");
		component.setReference("m_Material", UnityReference.material("506c261dd94da1d4c93293b19207e8b0"));
		Assert.stringEquals(component.getReference("m_Material").guid, "506c261dd94da1d4c93293b19207e8b0", "a reference reads back");
		Assert.equals(component.getReference("m_Material").type, 2, "with its type");
		component.setGuidReference("m_Texture", "9c82410a1332d86488bd33ba37ed63f9", Int64.ofInt(2800000), 3);
		Assert.stringEquals(component.getReference("m_Texture").guid, "9c82410a1332d86488bd33ba37ed63f9", "a GUID reference reads back");
		Assert.equals(Int64.toStr(component.getReference("m_Texture").fileId), "2800000", "with the file id it was given");
		var local = component.fileId();
		component.setLocalReference("m_ProbeAnchor", local);
		Assert.isTrue(component.getReference("m_ProbeAnchor").isLocal(), "a local reference has no GUID");
		Assert.isFalse(component.getReference("m_ProbeAnchor").isNone(), "and is not an empty one");

		step("sequences");
		component.setSeq("m_Materials", []);
		Assert.equals(component.getSeq("m_Materials").length(), 0, "a sequence can be emptied");
		component.addToSeq("m_Materials", UnityReference.material("506c261dd94da1d4c93293b19207e8b0").toNode());
		component.addToSeq("m_Materials", UnityReference.material("a97c105638bdf8b4a8650670310a4cd3").toNode());
		Assert.equals(component.getSeq("m_Materials").length(), 2, "entries append to a sequence");
		component.addToSeq("m_NewList", UnityReference.none().toNode());
		Assert.equals(component.getSeq("m_NewList").length(), 1, "a missing sequence is created on first append");

		step("flow mappings");
		component.setFlowMap("m_StaticBatchInfo", [{key: "firstSubMesh", value: 0}, {key: "subMeshCount", value: 2}]);
		Assert.contains(prefab.emit(), "m_StaticBatchInfo: {firstSubMesh: 0, subMeshCount: 2}", "a flow mapping is written inline");
		Assert.equals(component.getMap("m_StaticBatchInfo").getInt("subMeshCount"), 2, "and reads back");

		step("a component from a file still round trips");
		var real = UnityPrefab.fromFile(fixture("Prefabs/damGrp_8_s.prefab"));
		var renderer = real.find("Sprite_mesh").getComponent(ClassIds.MeshRenderer);
		renderer.setInt("m_SortingOrder", 7);
		Assert.contains(real.emit(), "m_SortingOrder: 7", "editing a parsed component writes the new value");
		Assert.equals(renderer.getSeq("m_Materials").length(), 1, "and leaves the rest of the component alone");
	}

	// -------------------------------------------------------------- references

	static function references():Void
	{
		Assert.test("Authoring.references");

		step("main object ids");
		Assert.equals(Int64.toStr(AssetClassifier.mainObjectIdOf("png")), "2800000", "a texture's main object id is public now");
		Assert.equals(Int64.toStr(AssetClassifier.mainObjectIdOf("mat")), "2100000", "a material's main object id");
		Assert.equals(Int64.toStr(AssetClassifier.mainObjectIdOf("prefab")), "100100000", "a prefab's reference id");
		Assert.equals(Int64.toStr(AssetClassifier.mainObjectIdOf("cs")), "11500000", "a script's main object id");
		Assert.isNull(AssetClassifier.mainObjectIdOf("fbx"), "an extension with no single main object reports none");

		step("typed references carry the file id and type Unity writes");
		var texture = UnityReference.texture("9c82410a1332d86488bd33ba37ed63f9");
		Assert.equals(Int64.toStr(texture.fileId), "2800000", "a texture reference uses fileID 2800000");
		Assert.equals(texture.type, 3, "a texture reference is type 3");
		var material = UnityReference.material("506c261dd94da1d4c93293b19207e8b0");
		Assert.equals(Int64.toStr(material.fileId), "2100000", "a material reference uses fileID 2100000");
		Assert.equals(material.type, 2, "a material reference is type 2");
		var prefab = UnityReference.prefab("75e48dfe44cab60438c20657f7f6f739");
		Assert.equals(Int64.toStr(prefab.fileId), "100100000", "a prefab reference uses fileID 100100000");
		Assert.equals(prefab.type, 3, "a prefab reference is type 3");
		var sprite = UnityReference.sprite("9c82410a1332d86488bd33ba37ed63f9", Int64.ofInt(21300002));
		Assert.equals(Int64.toStr(sprite.fileId), "21300002", "a sub sprite reference keeps the id it was given");
		Assert.equals(sprite.type, 3, "a sprite reference is type 3");
		var builtin = UnityReference.builtin(Int64.ofInt(10303));
		Assert.equals(builtin.type, 0, "a built in reference is type 0");
		Assert.equals(builtin.guid, "0000000000000000f000000000000000", "and uses the built in resources GUID");

		step("references are written the way Unity writes them");
		var node = material.toNode();
		Assert.isTrue(node.flow, "a reference is a flow mapping");
		Assert.stringEquals(node.entries[0].key, "fileID", "a reference starts with fileID");
		Assert.stringEquals(node.entries[0].value.toString(), "2100000", "and holds the file id");
		Assert.stringEquals(node.entries[1].key, "guid", "then the GUID");
		Assert.stringEquals(node.entries[2].key, "type", "then the type");
		Assert.stringEquals(node.entries[2].value.toString(), "2", "which is the type Unity writes for a material");

		step("the entry classifies what it always did");
		var meta = MetaFile.parse("fileFormatVersion: 2\nguid: aabbccddeeff00112233445566778899\nPrefabImporter:\n  externalObjects: {}\n");
		var entry = AssetClassifier.build(meta, "Assets/Hero.prefab", hxunity.unity.Origin.Project);
		Assert.isNull(entry.mainId, "a prefab still has no main object of its own");
		Assert.equals(entry.kind, hxunity.unity.AssetKind.Prefab, "and is still classified as a prefab");
	}

	// ------------------------------------------------------------------- index

	static function index():Void
	{
		Assert.test("Authoring.index");

		var root = SCRATCH + "/project";
		var assets = root + "/Assets/Psd/Hero";
		deleteTree(root);
		AssetWriter.ensureDirectory(assets);

		step("the cache starts empty");
		var cache = CachedGuidIndex.open(root);
		Assert.isFalse(cache.isLoaded(), "there is no cache file yet");
		var first = cache.refresh();
		Assert.isTrue(first.rebuilt, "the first refresh builds the index");
		Assert.equals(cache.size(), 0, "an empty project has no assets");

		step("a new asset is found by a directory refresh");
		var textureGuid = cache.newGuid();
		AssetWriter.saveBytes(assets + "/hand.png", haxe.io.Bytes.ofString("not really a png"));
		MetaWriter.forTexture(textureGuid, TextureImportSettings.sprite(100)).save(assets + "/hand.png.meta");
		var refreshed = cache.refreshDirectory("Assets/Psd/Hero");
		Assert.isFalse(refreshed.missing, "the directory exists");
		Assert.equals(refreshed.added.length, 1, "exactly one asset was added");
		Assert.stringEquals(refreshed.added[0], textureGuid, "and it is the one that was written");
		Assert.equals(refreshed.removed.length, 0, "nothing was removed");
		Assert.notNull(cache.index.locate(textureGuid), "the new GUID resolves");
		Assert.stringEquals(cache.index.locate(textureGuid).path, "Assets/Psd/Hero/hand.png", "to the path it was written at");

		step("the refresh survives a reopen");
		var reopened = CachedGuidIndex.open(root);
		Assert.isTrue(reopened.isLoaded(), "the cache file was written");
		Assert.notNull(reopened.index.locate(textureGuid), "and holds the new asset");
		var valid = reopened.refresh();
		Assert.isTrue(valid.valid, "nothing changed, so the cache is still valid");
		Assert.equals(valid.rescanedDirs.length, 0, "and no directory had to be re-read");

		step("a removed asset leaves the index");
		sys.FileSystem.deleteFile(assets + "/hand.png");
		sys.FileSystem.deleteFile(assets + "/hand.png.meta");
		var removed = reopened.refreshDirectory("Assets/Psd/Hero");
		Assert.equals(removed.removed.length, 1, "the deleted asset is reported as removed");
		Assert.stringEquals(removed.removed[0], textureGuid, "and it is the one that was deleted");

		step("a directory created by an export is walked");
		var deepGuid = reopened.newGuid();
		AssetWriter.ensureDirectory(assets + "/Extra");
		MetaWriter.forTexture(deepGuid, TextureImportSettings.sprite(100)).save(assets + "/Extra/extra.png.meta");
		var deep = reopened.refreshDirectory("Assets/Psd/Hero");
		Assert.stringEquals(deep.added.join(","), deepGuid, "an asset in a new subdirectory is indexed too");
		Assert.notNull(reopened.index.locate(deepGuid), "and resolves afterwards");

		step("a missing directory is reported");
		var missing = reopened.refreshDirectory("Assets/Nowhere");
		Assert.isTrue(missing.missing, "a directory that is not there says so");
		Assert.equals(missing.added.length, 0, "and adds nothing");

		step("scanDirectory still works");
		var direct = new AssetGuidIndex(root);
		var found = direct.scanDirectory("Assets/Psd/Hero/Extra");
		Assert.equals(found.length, 1, "scanning one directory reports what it indexed");
		Assert.stringEquals(found[0], deepGuid, "the GUID it found is the one on disk");
		Assert.notNull(direct.locate(deepGuid), "and it resolves");

		deleteTree(root);
	}

	// ------------------------------------------------------------------ writer

	static function writer():Void
	{
		Assert.test("Authoring.writer");

		// The suite has to be repeatable: every group that writes files starts by
		// clearing the directory it writes them into.
		deleteTree(SCRATCH + "/writer");
		deleteTree(SCRATCH + "/unique");

		step("paths");
		Assert.stringEquals(AssetWriter.metaPathOf("Assets/Art/hand.png"), "Assets/Art/hand.png.meta", "a .meta path is a suffix");
		Assert.stringEquals(AssetWriter.assetPathOf("Assets/Art/hand.png.meta"), "Assets/Art/hand.png", "and comes back off");
		Assert.stringEquals(AssetWriter.metaPathOf("Assets/Art"), "Assets/Art.meta", "a folder gets one too");
		Assert.isTrue(AssetWriter.isMetaPath("Assets/Art.meta"), "a .meta path is recognised");
		Assert.stringEquals(AssetWriter.assetPathOf("Assets/Art.png"), "Assets/Art.png", "a path that is not a .meta is left alone");

		step("text is written the way Unity writes it");
		Assert.stringEquals(AssetWriter.normaliseText("a\r\nb"), "a\nb\n", "CRLF becomes LF and the file ends with one newline");
		Assert.stringEquals(AssetWriter.normaliseText("a\n"), "a\n", "an existing trailing newline is kept as one");
		Assert.stringEquals(AssetWriter.normaliseText("a\n\n"), "a\n\n", "and a deliberate blank line is not removed");
		Assert.stringEquals(AssetWriter.normaliseText(null), "\n", "null writes an empty line");

		var path = SCRATCH + "/writer/notes.txt";
		Assert.isTrue(AssetWriter.saveText(path, "hello\r\nworld"), "text is written");
		Assert.stringEquals(read(path), "hello\nworld\n", "and lands as LF with a trailing newline");
		Assert.isFalse(sys.FileSystem.exists(path + ".tmp"), "the atomic write cleans up its temporary file");

		step("bytes are written unchanged");
		var bytes = haxe.io.Bytes.ofString("PNG");
		Assert.isTrue(AssetWriter.saveBytes(SCRATCH + "/writer/hand.png", bytes), "bytes are written");
		Assert.stringEquals(sys.io.File.getBytes(SCRATCH + "/writer/hand.png").toString(), "PNG", "and are unchanged");

		step("names are cleaned and made unique");
		Assert.stringEquals(AssetWriter.sanitiseName("hand/thumb:1"), "hand_thumb_1", "characters a file name cannot carry are replaced");
		Assert.stringEquals(AssetWriter.sanitiseName("  ..hidden  "), "hidden", "leading dots and surrounding spaces go");
		Assert.stringEquals(AssetWriter.sanitiseName("   "), "Asset", "a name that is only spaces falls back");
		Assert.stringEquals(AssetWriter.sanitiseName(null), "Asset", "so does no name at all");
		var dir = SCRATCH + "/unique";
		AssetWriter.ensureDirectory(dir);
		Assert.stringEquals(AssetWriter.uniqueFileName(dir, "hand", "png"), "hand.png", "the first name is the plain one");
		AssetWriter.saveText(dir + "/hand.png", "x");
		Assert.stringEquals(AssetWriter.uniqueFileName(dir, "hand", "png"), "hand 1.png", "a taken name gets Unity's numeric suffix");
		AssetWriter.saveText(dir + "/HAND 1.png", "x");
		Assert.stringEquals(AssetWriter.uniqueFileName(dir, "hand", "png"), "hand 2.png", "and the comparison is case insensitive");
		Assert.stringEquals(AssetWriter.uniqueFileName(dir, ".hidden", ".png"), "hidden.png", "an extension may come with or without its dot");

		step("directories");
		Assert.isTrue(AssetWriter.ensureDirectory(SCRATCH + "/deep/one/two"), "nested directories are created");
		Assert.isTrue(AssetWriter.exists(SCRATCH + "/deep/one/two"), "and exist afterwards");
		Assert.isTrue(AssetWriter.ensureDirectory(SCRATCH + "/deep/one/two"), "creating one twice is not an error");
	}

	// ----------------------------------------------------------------- factory

	static function factory():Void
	{
		Assert.test("Authoring.factory");

		var root = SCRATCH + "/export";
		deleteTree(root);
		AssetWriter.ensureDirectory(root + "/Assets");
		var index = new AssetGuidIndex(root);

		step("folders");
		var folder = UnityAssetFactory.ensureFolder(root, "Assets/Psd/Hero", index);
		Assert.notNull(folder, "the deepest folder has an entry");
		Assert.isTrue(sys.FileSystem.exists(root + "/Assets/Psd"), "the parent folder is created");
		Assert.isTrue(sys.FileSystem.exists(root + "/Assets/Psd.meta"), "and has a .meta");
		Assert.isTrue(sys.FileSystem.exists(root + "/Assets/Psd/Hero.meta"), "the deepest folder has one too");
		var folderMeta = MetaFile.parse(read(root + "/Assets/Psd.meta"));
		Assert.isTrue(folderMeta.isFolder, "the folder .meta declares a folder asset");
		Assert.notNull(index.locate(folderMeta.guid), "and the folder is in the index");

		step("a texture");
		var texture = UnityAssetFactory.createTexture(root, "Assets/Psd/Hero/hand.png", haxe.io.Bytes.ofString("PNG"),
			TextureImportSettings.sprite(100, new VectorData(0.5, 0.5)), index);
		Assert.isTrue(sys.FileSystem.exists(root + "/Assets/Psd/Hero/hand.png"), "the image is written");
		Assert.isTrue(sys.FileSystem.exists(root + "/Assets/Psd/Hero/hand.png.meta"), "and so is its .meta");
		Assert.isTrue(AssetGuid.isUsable(texture.guid), "the entry has a usable GUID");
		Assert.equals(texture.kind, hxunity.unity.AssetKind.Texture, "the entry is classified as a texture");
		Assert.equals(Int64.toStr(texture.mainId), "2800000", "with the main object id of a texture");
		Assert.notNull(index.locate(texture.guid), "the texture resolves through the index without a rescan");
		Assert.stringEquals(index.locate(texture.guid).path, "Assets/Psd/Hero/hand.png", "to the path it was exported to");

		step("a material that references the texture");
		var material = UnityAssetFactory.createMaterial(root, "Assets/Psd/Hero/hand.mat", null, "hand", index);
		Assert.equals(material.kind, hxunity.unity.AssetKind.NativeAsset, "the material is classified as a native asset");
		Assert.equals(Int64.toStr(material.mainId), "2100000", "with the main object id of a material");
		var readBack = UnityMaterial.fromFile(root + "/Assets/Psd/Hero/hand.mat");
		readBack.setTexture("_MainTex", texture.guid);
		readBack.setVector("_Pivot", new VectorData(0.5, 0.5));
		UnityAssetFactory.writeMaterial(root, "Assets/Psd/Hero/hand.mat", readBack, index);
		var finished = UnityMaterial.fromFile(root + "/Assets/Psd/Hero/hand.mat");
		// Re-exporting an asset keeps its identity: every reference to it is
		// already written down somewhere.
		Assert.stringEquals(UnityAssetFactory.resolveGuid(root, "Assets/Psd/Hero/hand.mat", null, index), material.guid,
			"rewriting a material keeps its GUID");
		Assert.stringEquals(finished.getTexture("_MainTex"), texture.guid, "the material points at the exported texture");
		Assert.equals(finished.getVector("_Pivot").y, 0.5, "and carries the pivot the exporter set");
		Assert.equals(finished.shader().type, 0, "with Unity's built in Standard shader by default");

		step("a prefab that uses them");
		var prefab = UnityPrefab.createEmpty();
		var object = prefab.createGameObject("hand");
		var renderer = object.addComponent("MeshRenderer");
		renderer.setSeq("m_Materials", [UnityReference.material(material.guid).toNode()]);
		var prefabEntry = UnityAssetFactory.createPrefab(root, "Assets/Psd/Hero/hand.prefab", prefab, index);
		Assert.equals(prefabEntry.kind, hxunity.unity.AssetKind.Prefab, "the prefab is classified as a prefab");
		Assert.notNull(index.locate(prefabEntry.guid), "and resolves through the index");
		var exported = UnityPrefab.fromFile(root + "/Assets/Psd/Hero/hand.prefab");
		var exportedRenderer = exported.find("hand").getComponent(ClassIds.MeshRenderer);
		Assert.stringEquals(UnityReference.fromNode(exportedRenderer.getSeq("m_Materials").get(0)).guid, material.guid,
			"the exported prefab references the exported material");

		step("the whole export is found by one directory refresh");
		var cache = CachedGuidIndex.open(root);
		var refreshed = cache.refreshDirectory("Assets/Psd/Hero");
		Assert.equals(refreshed.added.length, 3, "the exported assets are the ones the refresh found");
		Assert.notNull(cache.index.locate(texture.guid), "the texture resolves after the refresh");
		Assert.notNull(cache.index.locate(material.guid), "the material resolves after the refresh");
		Assert.notNull(cache.index.locate(prefabEntry.guid), "the prefab resolves after the refresh");

		deleteTree(root);
	}

	/** Removes a directory tree, ignoring a tree that is not there. **/
	static function deleteTree(path:String):Void
	{
		if (!sys.FileSystem.exists(path)) return;
		if (sys.FileSystem.isDirectory(path))
		{
			for (name in sys.FileSystem.readDirectory(path))
			{
				deleteTree(path + "/" + name);
			}
			sys.FileSystem.deleteDirectory(path);
			return;
		}
		sys.FileSystem.deleteFile(path);
	}
}
