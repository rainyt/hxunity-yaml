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
		map.set("keyword", new YamlScalar("yes", Plain));
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
		tricky.set("colon", new YamlScalar("a: b", Plain));
		tricky.set("hash", new YamlScalar("a #b", Plain));
		var trickyText = YamlWriter.write(tricky);
		Assert.contains(trickyText, "colon: 'a: b'", "a value containing a colon space is quoted");
		Assert.contains(trickyText, "hash: 'a #b'", "a value containing a hash is quoted");
		Assert.equals(YamlParser.parse(trickyText).asMap().getString("colon"), "a: b", "the quoted value reads back unchanged");
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
