package;

import haxe.Int64;
import hxunity.yaml.ClassIds;
import hxunity.yaml.UnityDocumentSet;
import hxunity.yaml.UnityYamlDocument;
import hxunity.yaml.YamlParser;
import hxunity.yaml.YamlWriter;
import hxunity.unity.FileId;
import hxunity.unity.UnityReference;
import hxunity.types.ColorData;
import hxunity.types.Numbers;
import hxunity.types.QuaternionData;
import hxunity.types.VectorData;

/** Tests for the Unity specific layer: class ids, references and value types. **/
class TestUnity
{
	public static function run():Void
	{
		// `HXU_ONLY` lets a debugging run execute a single sub test.
		var only = Sys.getEnv("HXU_ONLY");
		if (only != null && only.length > 0)
		{
			switch (only)
			{
				case "classIds": classIds();
				case "fileIds": fileIds();
				case "references": references();
				case "vectors": vectors();
				case "quaternions": quaternions();
				case "colors": colors();
				case "numbers": numbers();
				case "documentSet": documentSet();
				default: Sys.println("unknown sub test " + only);
			}
			return;
		}
		classIds();
		fileIds();
		references();
		vectors();
		quaternions();
		colors();
		numbers();
		documentSet();
	}

	/** Prints a progress marker so a hang points at the sub test. **/
	static function step(name:String):Void
	{
		TestMain.note("    step: " + name);
	}

	static function lines(parts:Array<String>):String
	{
		return parts.join("\n") + "\n";
	}

	static function classIds():Void
	{
		Assert.test("Unity.classIds");
		Assert.equals(ClassIds.name(1), "GameObject", "1 is GameObject");
		Assert.equals(ClassIds.name(4), "Transform", "4 is Transform");
		Assert.equals(ClassIds.name(114), "MonoBehaviour", "114 is MonoBehaviour");
		Assert.equals(ClassIds.name(224), "RectTransform", "224 is RectTransform");
		Assert.equals(ClassIds.name(1001), "PrefabInstance", "1001 is PrefabInstance");
		Assert.equals(ClassIds.name(1660057539), "SceneRoots", "the synthetic SceneRoots id is known");
		Assert.equals(ClassIds.name(999999), null, "an unknown id has no name");

		Assert.equals(ClassIds.id("Transform"), 4, "name to id");
		Assert.equals(ClassIds.id("NoSuchType"), -1, "an unknown name is -1");

		Assert.isTrue(ClassIds.isComponent(23), "MeshRenderer is a component");
		Assert.isTrue(ClassIds.isComponent(4), "Transform is listed in m_Component, so it counts as one");
		Assert.isTrue(ClassIds.isComponent(224), "RectTransform counts as a component");
		Assert.isFalse(ClassIds.isComponent(1), "GameObject is not a component");
		Assert.isFalse(ClassIds.isComponent(1001), "PrefabInstance is not a component");
		Assert.isTrue(ClassIds.isBehaviour(114), "MonoBehaviour is a behaviour");
		Assert.isTrue(ClassIds.isBehaviour(20), "Camera is a behaviour");
		Assert.isFalse(ClassIds.isBehaviour(23), "MeshRenderer is not a behaviour");

		Assert.equals(UnityYamlDocument.classNameOf(1), "GameObject", "the document helper agrees");
		Assert.equals(UnityYamlDocument.classNameOf(424242), "Class424242", "an unknown id gets a readable fallback");
	}

	static function fileIds():Void
	{
		Assert.test("Unity.fileIds");
		var big = FileId.ofString("8601872862307532784");
		Assert.equals(Int64.toStr(big), "8601872862307532784", "an id past 2^53 survives");
		Assert.equals(FileId.toStr(FileId.ofString("-8221572380872265284")), "-8221572380872265284", "a negative id survives");
		Assert.equals(FileId.toStr(null), "0", "a null id prints as 0");
		Assert.isTrue(FileId.isNone(null), "null is no reference");
		Assert.isTrue(FileId.isNone(FileId.zeroId()), "0 is no reference");
		Assert.isFalse(FileId.isNone(big), "a real id is a reference");
		Assert.equals(FileId.parse("nonsense"), null, "unparseable text is null");
		Assert.isTrue(FileId.fitsInt(Int64.ofInt(-42)), "a small id fits an Int");
		Assert.isFalse(FileId.fitsInt(big), "a large id does not fit an Int");
		Assert.isTrue(FileId.compare(Int64.ofInt(-10), Int64.ofInt(9)) < 0, "ids compare numerically, not as text");
	}

	static function references():Void
	{
		Assert.test("Unity.references");
		var root = YamlParser.parse(lines([
			"Transform:",
			"  local: {fileID: 8601872862307532784}",
			"  asset: {fileID: 2100000, guid: 053b4abb81615144aaca5038a766c6ef, type: 2}",
			"  none: {fileID: 0}",
			"  notAReference: 5"
		]));
		var map = root.asMap().getMap("Transform");

		var local = UnityReference.fromNode(map.get("local"));
		Assert.isTrue(local.isLocal(), "a reference without a guid is local");
		Assert.equals(Int64.toStr(local.fileId), "8601872862307532784", "the local id is exact");
		Assert.isFalse(local.isNone(), "a local reference to a real object is not none");

		var asset = UnityReference.fromNode(map.get("asset"));
		Assert.isTrue(asset.isExternal(), "a reference with a guid is external");
		Assert.equals(asset.guid, "053b4abb81615144aaca5038a766c6ef", "the guid is kept");
		Assert.equals(asset.type, UnityReference.TYPE_ASSET, "type 2 is an imported asset");

		Assert.isTrue(UnityReference.fromNode(map.get("none")).isNone(), "{fileID: 0} is none");
		Assert.isNull(UnityReference.fromNode(map.get("notAReference")), "a scalar field is not a reference");

		// Writing a reference back has to reproduce Unity's field order.
		var written = hxunity.yaml.YamlWriter.write(asset.toNode());
		Assert.stringEquals(written, "{fileID: 2100000, guid: 053b4abb81615144aaca5038a766c6ef, type: 2}\n",
			"a reference is written as Unity writes it");
		Assert.stringEquals(hxunity.yaml.YamlWriter.write(UnityReference.none().toNode()), "{fileID: 0}\n",
			"an empty reference is written as {fileID: 0}");
		Assert.stringEquals(hxunity.yaml.YamlWriter.write(UnityReference.local(FileId.ofString("42")).toNode()), "{fileID: 42}\n",
			"a local reference has no guid and no type");

		Assert.isTrue(UnityReference.local(Int64.ofInt(7)).equals(UnityReference.local(Int64.ofInt(7))), "equal local references");
		Assert.isFalse(UnityReference.local(Int64.ofInt(7)).equals(UnityReference.local(Int64.ofInt(8))), "different local references");
		Assert.isFalse(UnityReference.local(Int64.ofInt(7)).equals(UnityReference.asset("guid", Int64.ofInt(7), 2)),
			"a local and an external reference over the same id differ");
	}

	static function vectors():Void
	{
		Assert.test("Unity.vectors");
		var three = VectorData.fromNode(YamlParser.parse(lines(["v: {x: 0.129, y: -1.932, z: 0}"])).asMap().get("v"));
		Assert.equals(three.x, 0.129, "x");
		Assert.equals(three.y, -1.932, "y");
		Assert.equals(three.z, 0.0, "z");
		Assert.isTrue(three.hasZ, "the source had a z");
		Assert.isFalse(three.hasW, "the source had no w");
		Assert.stringEquals(YamlWriter.write(three.toNode()), "{x: 0.129, y: -1.932, z: 0}\n", "a Vector3 is written back unchanged");

		var two = VectorData.fromNode(YamlParser.parse(lines(["v: {x: 1, y: 1}"])).asMap().get("v"));
		Assert.isFalse(two.hasZ, "a Vector2 has no z");
		Assert.stringEquals(YamlWriter.write(two.toNode()), "{x: 1, y: 1}\n", "a Vector2 does not gain a z");
		Assert.stringEquals(two.toString(), "(1, 1)", "a Vector2 prints as two components");

		var four = VectorData.fromNode(YamlParser.parse(lines(["v: {x: 1, y: 2, z: 3, w: 4}"])).asMap().get("v"));
		Assert.equals(four.w, 4.0, "w is read");
		Assert.stringEquals(four.toString(), "(1, 2, 3, 4)", "a Vector4 prints as four components");
	}

	static function quaternions():Void
	{
		Assert.test("Unity.quaternions");
		var rotation = QuaternionData.fromNode(YamlParser.parse(lines(["q: {x: -0, y: -0, z: -0, w: 1}"])).asMap().get("q"));
		Assert.equals(rotation.w, 1.0, "w is read");
		Assert.stringEquals(YamlWriter.write(rotation.toNode()), "{x: -0, y: -0, z: -0, w: 1}\n",
			"the negative zero Unity writes for rotations is preserved");
		Assert.equals(Numbers.format(-0.0), "-0", "-0.0 formats as -0");
		Assert.equals(Numbers.format(0.0), "0", "0.0 formats as 0");
		Assert.equals(Numbers.format(0.7071068), "0.7071068", "a rotation component keeps its precision");
		Assert.equals(Numbers.format(1.0), "1", "a whole float loses its decimal part");
	}

	static function colors():Void
	{
		Assert.test("Unity.colors");
		var color = ColorData.fromHex("#FF8000");
		Assert.equals(Math.round(color.r * 255), 255, "red channel");
		Assert.equals(Math.round(color.g * 255), 128, "green channel");
		Assert.equals(Math.round(color.b * 255), 0, "blue channel");
		Assert.equals(color.a, 1.0, "alpha defaults to opaque");
		Assert.equals(ColorData.fromHex("#FF800080").toHex(), "#FF800080", "eight digit hex round trips");
		Assert.stringEquals(YamlWriter.write(new ColorData(1, 0.5, 0, 1).toNode()), "{r: 1, g: 0.5, b: 0, a: 1}\n",
			"a colour is written in Unity's component order");
	}

	static function numbers():Void
	{
		Assert.test("Unity.numbers");
		Assert.equals(Numbers.format(10), "10", "an integer stays integral");
		Assert.equals(Numbers.format(-1.932), "-1.932", "a negative float keeps its digits");
		Assert.equals(Numbers.format(0.06), "0.06", "a small float keeps its digits");
		Assert.equals(Numbers.format(1e-5), "0.00001", "a small exponent expands rather than using e notation");
	}

	static function documentSet():Void
	{
		Assert.test("Unity.documentSet");
		var crlf = lines([
			"%YAML 1.1",
			"%TAG !u! tag:unity3d.com,2011:",
			"--- !u!1 &1",
			"GameObject:",
			"  m_Name: hero"
		]).split("\n").join("\r\n");
		var set = UnityDocumentSet.parse(crlf);
		Assert.equals(set.lineEnding, "\r\n", "CRLF is detected");
		Assert.stringEquals(set.emit(), crlf, "CRLF is reproduced on write");
		Assert.isTrue(set.trailingNewline, "the trailing newline is remembered");

		var noTrailing = "%YAML 1.1\n--- !u!1 &1\nGameObject:\n  m_Name: hero";
		var set2 = UnityDocumentSet.parse(noTrailing);
		Assert.isFalse(set2.trailingNewline, "a file without a trailing newline is detected");
		Assert.stringEquals(set2.emit(), noTrailing, "a file without a trailing newline stays that way");

		var meta = UnityDocumentSet.parse(lines([
			"fileFormatVersion: 2",
			"guid: fea157dfd84dee94f80991aca36dd03c",
			"PrefabImporter:",
			"  externalObjects: {}",
			"  userData: ",
			"  assetBundleName: ",
			"  assetBundleVariant: "
		]));
		Assert.equals(meta.count(), 1, "a .meta file yields one document");
		Assert.isFalse(meta.at(0).hasHeader, "the document has no --- header");
		Assert.equals(meta.at(0).className(), "Document", "an id of 0 maps to Document");
		Assert.contains(meta.emit(), "fileFormatVersion: 2", "a .meta body is written back");
		Assert.notContains(meta.emit(), "--- !u!", "no header is invented for a .meta file");

		var added = set.newFileId();
		Assert.notNull(added, "a fresh id is produced");
		Assert.isTrue(Int64.compare(added, Int64.ofInt(0)) > 0, "a fresh id is positive");
		Assert.isFalse(set.contains(added), "a fresh id is not already used");
	}
}
