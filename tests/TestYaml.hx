package;

import hxunity.yaml.YamlLexer;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlParser;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.YamlSeq;
import hxunity.yaml.YamlTokenType;
import hxunity.yaml.YamlWriter;
import hxunity.yaml.ScalarKind;
import hxunity.yaml.UnityDocumentSet;
import hxunity.yaml.YamlError;

/** Tests for the YAML reader and writer. **/
class TestYaml
{
	public static function run():Void
	{
		blockStructure();
		sequences();
		flowCollections();
		wrappedFlow();
		wrappedQuotedScalar();
		unityCorpusShapes();
		deepClone();
		quotedStyles();
		blockScalars();
		documents();
		roundTrip();
		writerQuoting();
		errors();
	}

	// ------------------------------------------------------------------ fixtures

	/** Joins lines with `\n`, keeping the literal readable in the source. **/
	static function lines(parts:Array<String>):String
	{
		return parts.join("\n") + "\n";
	}

	static function simplePrefab():String
	{
		return lines([
			"%YAML 1.1",
			"%TAG !u! tag:unity3d.com,2011:",
			"--- !u!1 &338340333028156454",
			"GameObject:",
			"  m_ObjectHideFlags: 0",
			"  m_CorrespondingSourceObject: {fileID: 0}",
			"  m_Component:",
			"  - component: {fileID: 8601872862307532784}",
			"  m_Layer: 0",
			"  m_Name: alex_fat",
			"  m_IsActive: 1",
			"--- !u!4 &8601872862307532784",
			"Transform:",
			"  m_GameObject: {fileID: 338340333028156454}",
			"  serializedVersion: 2",
			"  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}",
			"  m_LocalPosition: {x: 0.129, y: -1.932, z: 0}",
			"  m_Children: []",
			"  m_Father: {fileID: 0}",
			"  m_LocalEulerAnglesHint: {x: -0, y: -0, z: -0}"
		]);
	}

	// --------------------------------------------------------------------- tests

	static function blockStructure():Void
	{
		Assert.test("Yaml.blockStructure");
		var root = YamlParser.parse(lines([
			"GameObject:",
			"  m_Name: hero",
			"  m_IsActive: 1",
			"  nested:",
			"    deep:",
			"      value: 3"
		]));
		var map = root.asMap();
		Assert.equals(map.size(), 1, "one top level key");
		var gameObject = map.getMap("GameObject");
		Assert.notNull(gameObject, "the class-name key holds a mapping");
		Assert.equals(gameObject.getString("m_Name"), "hero", "string field");
		Assert.equals(gameObject.getInt("m_IsActive"), 1, "int field");
		Assert.equals(gameObject.getFloat("missing"), null, "absent field reads as null");
		Assert.equals(gameObject.getMap("nested").getMap("deep").getInt("value"), 3, "three levels of nesting");
		Assert.equals(map.getString("GameObject"), null, "a collection is not readable as a scalar");

		// Field order must survive, because Unity's own order is what a written
		// file is compared against.
		var keys = [];
		for (entry in gameObject.entries)
		{
			keys.push(entry.key);
		}
		Assert.equals(keys.join(","), "m_Name,m_IsActive,nested", "field order is preserved");
	}

	static function sequences():Void
	{
		Assert.test("Yaml.sequences");
		var root = YamlParser.parse(lines([
			"GameObject:",
			"  m_Component:",
			"  - component: {fileID: 1}",
			"  - component: {fileID: 2}",
			"  - ",
			"  m_Other: 5",
			"  m_Scalars:",
			"  - one",
			"  - two",
			"  m_Empty: []"
		]));
		var gameObject = root.asMap().getMap("GameObject");
		var component = gameObject.getSeq("m_Component");
		Assert.equals(component.length(), 3, "three dash items, including the empty one");
		Assert.equals(component.get(0).asMap().getMap("component").getString("fileID"), "1", "first item mapping");
		Assert.isTrue(component.get(2).isNull(), "a trailing bare dash is a null item");
		Assert.equals(gameObject.getInt("m_Other"), 5, "the sibling after the sequence is not swallowed");
		Assert.equals(gameObject.getSeq("m_Scalars").toStrings().join(","), "one,two", "block sequence of scalars");
		Assert.isTrue(gameObject.getSeq("m_Empty").isEmpty(), "[] parses as an empty sequence");
		Assert.equals(gameObject.getSeq("m_Empty").toStrings().length, 0, "empty sequence has no items");
	}

	static function flowCollections():Void
	{
		Assert.test("Yaml.flowCollections");
		var root = YamlParser.parse(lines([
			"Transform:",
			"  m_Ref: {fileID: 2100000, guid: 053b4abb81615144aaca5038a766c6ef, type: 2}",
			"  m_None: {fileID: 0}",
			"  m_List: []",
			"  m_Numbers: [1, 2, 3]",
			"  m_Color: {r: 1, g: 0.5, b: 0, a: 1}"
		]));
		var transform = root.asMap().getMap("Transform");
		var reference = transform.getMap("m_Ref");
		Assert.isTrue(reference.flow, "the mapping is remembered as flow style");
		Assert.equals(reference.size(), 3, "three reference fields");
		Assert.equals(reference.getString("fileID"), "2100000", "fileID");
		Assert.equals(reference.getString("guid"), "053b4abb81615144aaca5038a766c6ef", "guid stays text");
		Assert.equals(reference.getInt("type"), 2, "type is a number");
		Assert.equals(transform.getMap("m_None").size(), 1, "a single entry flow map");
		Assert.isTrue(transform.getSeq("m_List").flow, "[] is a flow sequence");
		Assert.equals(transform.getSeq("m_Numbers").toStrings().join(","), "1,2,3", "flow sequence of scalars");
		Assert.isTrue(transform.getMap("m_Color").flow, "a colour is flow style");
	}

	static function wrappedFlow():Void
	{
		Assert.test("Yaml.wrappedFlow");
		// Unity breaks a long flow mapping after a comma and indents the
		// continuation by max(4, indent + 4).
		var source = lines([
			"%YAML 1.1",
			"%TAG !u! tag:unity3d.com,2011:",
			"--- !u!1001 &5693881486261822889",
			"PrefabInstance:",
			"  serializedVersion: 2",
			"  m_Modification:",
			"    m_Modifications:",
			"    - target: {fileID: 4511153011648551893, guid: 75e48dfe44cab60438c20657f7f6f739,",
			"        type: 3}",
			"      propertyPath: m_Name",
			"      value: banquet_0205_14",
			"      objectReference: {fileID: 0}",
			"    m_RemovedComponents: []",
			"  m_SourcePrefab: {fileID: 100100000, guid: 75e48dfe44cab60438c20657f7f6f739, type: 3}",
			"--- !u!4 &8187102978003566204 stripped",
			"Transform:",
			"  m_CorrespondingSourceObject: {fileID: 4511153011648551893, guid: 75e48dfe44cab60438c20657f7f6f739,",
			"    type: 3}",
			"  m_PrefabInstance: {fileID: 5693881486261822889}",
			"  m_PrefabAsset: {fileID: 0}"
		]);
		var set = UnityDocumentSet.parse(source);
		Assert.equals(set.count(), 2, "two documents");
		Assert.isTrue(set.at(1).stripped, "the second document is marked stripped");
		Assert.equals(set.at(0).classId, 1001, "PrefabInstance class id");

		var prefabInstance = set.at(0).body.asMap().getMap("PrefabInstance");
		var modifications = prefabInstance.getMap("m_Modification").getSeq("m_Modifications");
		Assert.equals(modifications.length(), 1, "one modification entry");
		var modification = modifications.get(0).asMap();
		Assert.equals(modification.getMap("target").getString("fileID"), "4511153011648551893", "wrapped flow map kept its fileID");
		Assert.equals(modification.getMap("target").getString("guid"), "75e48dfe44cab60438c20657f7f6f739", "wrapped flow map kept its guid");
		Assert.equals(modification.getMap("target").getInt("type"), 3, "wrapped flow map kept its type");
		Assert.equals(modification.getString("propertyPath"), "m_Name", "the key after a wrapped map is a sibling");
		Assert.equals(modification.getString("value"), "banquet_0205_14", "value field");
		Assert.equals(prefabInstance.getMap("m_SourcePrefab").getString("guid"), "75e48dfe44cab60438c20657f7f6f739", "m_SourcePrefab");

		var strippedTransform = set.at(1).body.asMap().getMap("Transform");
		Assert.equals(strippedTransform.getMap("m_CorrespondingSourceObject").getInt("type"), 3, "stripped document wrapped map");
	}

	static function wrappedQuotedScalar():Void
	{
		Assert.test("Yaml.wrappedQuotedScalar");
		// Unity folds a long single quoted JSON blob across lines with a
		// max(4, indent + 4) continuation indent, and folding turns the break
		// back into a space.
		var source = lines([
			"MonoBehaviour:",
			"  m_Name: ",
			"  _serializedGraph: '{\"type\":\"NodeCanvas.DialogueTrees.DialogueTree\",\"nodes\":[{\"gridPosition\":{\"x\":103.0,\"y\":130.0},",
			"    \"positionDir\":4,\"$type\":\"Action_CreateNPC\"}],\"canvasGroups\":null,\"localBlackboard\":{\"_variables\":{\"Separator|",
			"    (Double Click To Rename)\":{\"_value\":{},\"_name\":\"Separator (Double Click To Rename)\"}}}}'",
			"  _objectReferences: []"
		]);
		var root = YamlParser.parse(source);
		var behaviour = root.asMap().getMap("MonoBehaviour");
		var graph = behaviour.getString("_serializedGraph");
		Assert.notNull(graph, "the folded scalar was read");
		Assert.notContains(graph, "\n", "a line break folds into a space, not a newline");
		// The fold before `"positionDir"` follows a comma, and YAML folding inserts
		// the space, so the value legitimately has one there.
		Assert.contains(graph, "\"y\":130.0}, \"positionDir\":4", "the first fold put a space back");
		Assert.contains(graph, "\"Separator| (Double Click To Rename)\"", "the second fold put a space back");
		Assert.contains(graph, "Separator (Double Click To Rename)", "the folded key text is intact");
		Assert.equals(behaviour.getSeq("_objectReferences").length(), 0, "the next field is a sibling, not part of the scalar");
		var graphNode = root.asMap().getMap("MonoBehaviour").get("_serializedGraph");
		Assert.equals(Type.getClassName(Type.getClass(graphNode)), "hxunity.yaml.YamlScalar", "the graph field is a scalar node");
		Assert.isTrue(graphNode.asScalar().isQuoted(), "the scalar remembers it was quoted");

		// A wrapped scalar must survive a write/read cycle with the same value.
		var emitted = YamlWriter.write(root, {flowLineWidth: 100});
		var reparsed = YamlParser.parse(emitted);
		Assert.equals(reparsed.asMap().getMap("MonoBehaviour").getString("_serializedGraph"), graph,
			"a wrapped quoted scalar round trips through the writer");
	}

	/**
		The shapes real Unity 2022.3 files contain that earlier revisions of the
		reader and writer got wrong, kept as regression tests.
	**/
	static function unityCorpusShapes():Void
	{
		Assert.test("Yaml.unityCorpusShapes");

		// A block plain scalar may contain flow indicators: Unity writes
		// `Array.data[N]` property paths unquoted in every PrefabInstance whose
		// modification touches an array element.
		var propertyPath = lines([
			"--- !u!1001 &5085980170101733206",
			"PrefabInstance:",
			"  m_ObjectHideFlags: 0",
			"  m_Modification:",
			"    m_Modifications:",
			"    - target: {fileID: 2134456498145251588, guid: 84ae5d92e288662409880540cd60e849,",
			"        type: 3}",
			"      propertyPath: AnimateDatas.Array.data[1].ChildTargetDatas.Array.data[5].Target",
			"      value: ",
			"      objectReference: {fileID: 0}"
		]);
		var set = UnityDocumentSet.parse(propertyPath);
		var mods = set.at(0).body.asMap().getMap("PrefabInstance").getMap("m_Modification").getSeq("m_Modifications");
		var entry = mods.get(0).asMap();
		Assert.equals(entry.getString("propertyPath"), "AnimateDatas.Array.data[1].ChildTargetDatas.Array.data[5].Target",
			"a property path with [N] stays one scalar");
		Assert.equals(entry.getString("value"), "", "an empty value stays empty instead of eating the next key");
		Assert.isTrue(entry.has("objectReference"), "objectReference is a sibling key, not part of the value");
		Assert.stringEquals(set.emit(), propertyPath, "the modification block round trips byte for byte");

		// A sequence item whose first value is a block mapping (`- _BaseMap:`
		// with the texture fields under it, as in every m_TexEnvs entry).
		var texEnv = lines([
			"Material:",
			"  m_SavedProperties:",
			"    m_TexEnvs:",
			"    - _BaseMap:",
			"        m_Texture: {fileID: 2800000, guid: 0fe8eb18f29c1a744a6eabb02458e243, type: 3}",
			"        m_Scale: {x: 1, y: 1}",
			"        m_Offset: {x: 0, y: 0}"
		]);
		var materialSet = UnityDocumentSet.parse(texEnv);
		var baseMap = materialSet.at(0).body.asMap().getMap("Material").getMap("m_SavedProperties").getSeq("m_TexEnvs").get(0).asMap();
		Assert.equals(baseMap.getMap("_BaseMap").getMap("m_Scale").getFloat("x"), 1.0, "the block mapping under - _BaseMap: is kept");
		Assert.stringEquals(materialSet.emit(), texEnv, "the m_TexEnvs entry round trips byte for byte");

		// Unity wraps a flow reference when a comma lands past column 80 and
		// indents the continuation by the owning key's column + 2: key at 2 wraps
		// to 4, a `- target:` at dash indent 4 wraps to 8. A reference that fits
		// within 80 stays on one line.
		var wrapped = lines([
			"Transform:",
			"  m_CorrespondingSourceObject: {fileID: 1065216990777830565, guid: 71b9c6d26ba88d249bcca7c2a2797344,",
			"    type: 3}",
			"  m_PrefabInstance: {fileID: 59793306554695430}",
			"  m_AppLauncherInfo: {fileID: 11400000, guid: f05bbc955b417714cad1bc50746e7f5b, type: 2}"
		]);
		var wrappedSet = UnityDocumentSet.parse(wrapped);
		Assert.stringEquals(wrappedSet.emit(), wrapped, "a wrapped flow map is re-wrapped in place");

		var dashWrapped = lines([
			"PrefabInstance:",
			"  m_Modification:",
			"    m_Modifications:",
			"    - target: {fileID: 37593701593205812, guid: 68c32c843c8314f479ba12ccfa26b5d1,",
			"        type: 3}",
			"      propertyPath: m_LocalPosition.x",
			"      value: -0.58"
		]);
		Assert.stringEquals(UnityDocumentSet.parse(dashWrapped).emit(), dashWrapped, "a wrapped - target: flow map round trips");

		// Unity escapes every non-ASCII character as \uXXXX, so a parsed escaped
		// name is written back escaped rather than as raw UTF-8.
		var escaped = YamlParser.parse("m_Name: \"\\u7269\\u4EF6\"\n");
		Assert.equals(escaped.asMap().getString("m_Name"), "物件", "the escaped name decodes");
		Assert.stringEquals(YamlWriter.write(escaped), "m_Name: \"\\u7269\\u4EF6\"\n", "the escape style is kept");

		// A plain keyword Unity wrote stays bare; ofString is what quotes
		// programmatic values.
		var keyword = YamlWriter.write(YamlParser.parse("folderAsset: yes\n"));
		Assert.stringEquals(keyword, "folderAsset: yes\n", "a parsed plain keyword is not re-quoted");

		// Empty values keep their separator: importer meta files write
		// `userData:` with no trailing space, scene files write `value: ` with.
		var meta = lines([
			"fileFormatVersion: 2",
			"guid: fe66738c18dcdcf488e1f64c48c6986d",
			"NativeFormatImporter:",
			"  externalObjects: {}",
			"  mainObjectFileID: 0",
			"  userData:",
			"  assetBundleName:",
			"  assetBundleVariant:"
		]);
		Assert.stringEquals(UnityDocumentSet.parse(meta).emit(), meta, "an importer meta's colon spacing round trips");

		// A UTF-8 BOM is written back, and a file that ends without a newline
		// stays that way.
		var bomMeta = "﻿fileFormatVersion: 2\nguid: 0b8d4906c5154f3f8c4ef037bd28f986\ntimeCreated: 1766394426";
		Assert.stringEquals(UnityDocumentSet.parse(bomMeta).emit(), bomMeta, "a BOM and a missing trailing newline round trip");

		// A plain value Unity wrapped across lines folds into one string and is
		// re-wrapped in place: Odin rule configs write long assembly names so.
		var folded = lines([
			"Rules:",
			"  - Enabled: 1",
			"    Type: Sirenix.OdinValidator.Editor.Validators.UICanvasChildElementValidator,",
			"      Sirenix.OdinValidator.Editor",
			"    Override: "
		]);
		var rulesSet = UnityDocumentSet.parse(folded);
		var rule = rulesSet.at(0).body.asMap().getSeq("Rules").get(0).asMap();
		Assert.equals(rule.getString("Type"), "Sirenix.OdinValidator.Editor.Validators.UICanvasChildElementValidator, Sirenix.OdinValidator.Editor",
			"a wrapped plain value folds into one string");
		Assert.stringEquals(rulesSet.emit(), folded, "the wrapped plain value is re-wrapped in place");

		// The empty-string key of every plugin importer's platformData block.
		var pluginMeta = lines([
			"PluginImporter:",
			"  platformData:",
			"  - first:",
			"      '': Any",
			"    second:",
			"      enabled: 0",
			"      settings: {}"
		]);
		var pluginSet = UnityDocumentSet.parse(pluginMeta);
		var first = pluginSet.at(0).body.asMap().getMap("PluginImporter").getSeq("platformData").get(0).asMap();
		Assert.equals(first.getMap("first").getString(""), "Any", "the quoted empty key is read");
		Assert.stringEquals(pluginSet.emit(), pluginMeta, "the platformData block round trips byte for byte");
	}

	static function deepClone():Void
	{
		Assert.test("Yaml.deepClone");
		// 覆盖各类保真形态：转义引号标量、折行流式映射、折行纯文本、无空格空值
		var source = lines([
			"%YAML 1.1",
			"%TAG !u! tag:unity3d.com,2011:",
			"--- !u!1 &100",
			"GameObject:",
			"  m_Name: \"\\u7269\\u4EF6\"",
			"  m_TagString: Untagged",
			"  m_LocalPosition: {x: 1, y: 2}",
			"  m_Components:",
			"  - component: {fileID: 12345678901234567, guid: 71b9c6d26ba88d249bcca7c2a2797344,",
			"      type: 3}",
			"  m_Rule: Sirenix.OdinValidator.Editor.Validators.UICanvasChildElementValidator,",
			"    Sirenix.OdinValidator.Editor",
			"  userData:"
		]);
		var set = UnityDocumentSet.parse(source);
		var clone = set.clone();
		Assert.stringEquals(clone.emit(), source, "a cloned set emits byte-identical text");
		Assert.stringEquals(set.clone().clone().emit(), source, "cloning is stable through copies");

		// 独立性：改克隆的任意节点，原件逐字节不变
		clone.documents[0].body.asMap().getMap("GameObject").get("m_Name").asScalar().setRaw("Changed");
		clone.documents[0].body.asMap().getMap("GameObject").set("m_Added", hxunity.yaml.Scalars.ofString("new"));
		Assert.stringEquals(set.emit(), source, "mutating the clone leaves the original byte identical");
		Assert.equals(set.documents[0].body.asMap().getMap("GameObject").getString("m_Name"), "物件",
			"the original keeps its decoded value");
	}

	static function quotedStyles():Void
	{
		Assert.test("Yaml.quotedStyles");
		var root = YamlParser.parse(lines([
			"a: plain",
			"b: 'single'",
			"c: \"double\"",
			"d: 'it''s escaped'",
			"e: \"tab\\there\"",
			"f: 'true'"
		]));
		var map = root.asMap();
		Assert.equals(map.get("a").asScalar().kind, Plain, "plain style recorded");
		Assert.equals(map.get("b").asScalar().kind, SingleQuoted, "single quoted style recorded");
		Assert.equals(map.get("c").asScalar().kind, DoubleQuoted, "double quoted style recorded");
		Assert.equals(map.getString("d"), "it's escaped", "doubled single quote decodes");
		Assert.equals(map.getString("e"), "tab\there", "double quoted escape decodes");
		Assert.equals(map.getString("f"), "true", "a quoted keyword stays a string");
		Assert.isFalse(map.get("f").asScalar().isPlain(), "quoted keyword is not plain");
	}

	static function blockScalars():Void
	{
		Assert.test("Yaml.blockScalars");
		var root = YamlParser.parse(lines([
			"literal: |",
			"  line one",
			"  line two",
			"folded: >",
			"  one",
			"  two",
			"after: 1"
		]));
		var map = root.asMap();
		// The default clip chomping keeps exactly one trailing line break.
		Assert.equals(map.getString("literal"), "line one\nline two\n", "literal block keeps newlines");
		Assert.equals(map.getString("folded"), "one two\n", "folded block joins lines with a space");
		Assert.equals(map.getInt("after"), 1, "the block scalar stops at a less indented key");
		Assert.equals(map.get("literal").asScalar().kind, Literal, "literal style recorded");
		Assert.equals(map.get("folded").asScalar().kind, Folded, "folded style recorded");

		var stripped = YamlParser.parse(lines(["s: |-", "  body", "after: 2"])).asMap();
		Assert.equals(stripped.getString("s"), "body", "|- strips the trailing break");
		Assert.equals(stripped.getInt("after"), 2, "the key after |- is a sibling");
	}

	static function documents():Void
	{
		Assert.test("Yaml.documents");
		var set = UnityDocumentSet.parse(simplePrefab());
		Assert.equals(set.count(), 2, "two documents");
		Assert.equals(set.preamble.join("|"), "%YAML 1.1|%TAG !u! tag:unity3d.com,2011:", "both directives captured");
		Assert.equals(set.at(0).classId, 1, "first class id");
		Assert.equals(set.at(0).className(), "GameObject", "class name from the table");
		Assert.equals(set.at(0).bodyName, "GameObject", "class name from the body");
		Assert.equals(set.at(1).classId, 4, "second class id");
		Assert.equals(set.at(1).className(), "Transform", "second class name");
		Assert.equals(haxe.Int64.toStr(set.at(1).fileId), "8601872862307532784", "anchor becomes the file id");
		Assert.notNull(set.byIdText("8601872862307532784"), "an anchor is findable by id");
		Assert.equals(set.byIdText("does-not-exist"), null, "an unknown id is not found");
	}

	static function roundTrip():Void
	{
		Assert.test("Yaml.roundTrip");
		var source = simplePrefab();
		var set = UnityDocumentSet.parse(source);
		Assert.stringEquals(set.emit(), source, "a parsed prefab is written back byte for byte");
	}

	static function writerQuoting():Void
	{
		Assert.test("Yaml.writerQuoting");
		var map = new YamlMap();
		map.set("plain", new YamlScalar("hero", Plain));
		// ofString is the programmatic entry point: it quotes the values that a
		// bare write would not read back as the same string.
		map.set("keyword", hxunity.yaml.Scalars.ofString("yes"));
		map.set("number", new YamlScalar("10", Plain));
		map.set("negative", new YamlScalar("-0.02", Plain));
		map.set("empty", new YamlScalar("", Plain));
		map.set("quoted", new YamlScalar("kept", SingleQuoted));
		map.set("ref", hxunity.unity.UnityReference.none().toNode());
		var text = YamlWriter.write(map);
		Assert.contains(text, "plain: hero", "a plain string stays unquoted");
		Assert.contains(text, "keyword: 'yes'", "a keyword is quoted");
		Assert.contains(text, "number: 10", "a number stays bare");
		Assert.contains(text, "negative: -0.02", "a negative number stays bare");
		Assert.contains(text, "empty: ", "an empty value leaves a trailing space");
		Assert.contains(text, "quoted: 'kept'", "a quoted scalar keeps its style");
		Assert.contains(text, "ref: {fileID: 0}", "a single entry flow map stays inline");

		// Text that would change meaning unquoted has to be quoted.
		var tricky = new YamlMap();
		tricky.set("colon", hxunity.yaml.Scalars.ofString("a: b"));
		tricky.set("hash", hxunity.yaml.Scalars.ofString("a #b"));
		var trickyText = YamlWriter.write(tricky);
		Assert.contains(trickyText, "colon: 'a: b'", "a value containing a colon space is quoted");
		Assert.contains(trickyText, "hash: 'a #b'", "a value containing a hash is quoted");
		Assert.equals(YamlParser.parse(trickyText).asMap().getString("colon"), "a: b", "the quoted value reads back unchanged");

		// A plain keyword that Unity itself wrote stays bare: the writer keeps
		// the original style instead of re-quoting it.
		var round = YamlParser.parse("keyword: yes\nname: hero\n");
		var roundText = YamlWriter.write(round);
		Assert.stringEquals(roundText, "keyword: yes\nname: hero\n", "a parsed plain keyword is written back bare");
	}

	static function errors():Void
	{
		Assert.test("Yaml.errors");
		var error = Assert.throws(function()
		{
			YamlParser.parse(lines(["a: 1", "b: [1, 2"]));
		}, "an unterminated flow sequence throws");
		Assert.notNull(error, "the error object exists");
		Assert.contains(Std.string(error), "unterminated", "the message names the problem");

		var duplicate = Assert.throws(function()
		{
			YamlParser.parse(lines(["a: 1", "a: 2"]), {rejectDuplicateKeys: true});
		}, "a duplicate key throws when the option is on");
		Assert.contains(Std.string(duplicate), "duplicate", "the message names the duplicate");

		Assert.notNull(YamlParser.parse(lines(["a: 1", "a: 2"])), "duplicates are allowed by default");
	}

	/** Lexer smoke test: the token stream has to expose indentation. **/
	public static function lexer():Void
	{
		Assert.test("Yaml.lexer");
		var lexer = new YamlLexer(lines(["a:", "  b: 1"]));
		var first = lexer.next();
		Assert.equals(first.type, Key, "first token is a key");
		Assert.equals(first.text, "a", "key text");
		Assert.equals(first.indent, 0, "key at column 0");
		var second = lexer.next();
		Assert.equals(second.type, Key, "second token is a key");
		Assert.equals(second.indent, 2, "indent is reported for the nested line");
		var third = lexer.next();
		Assert.equals(third.type, Scalar, "third token is a scalar");
		Assert.equals(third.text, "1", "scalar text");
	}
}
