package;

import haxe.Int64;
import sys.FileSystem;
import hxunity.prefab.GameObjectObject;
import hxunity.prefab.MonoBehaviourObject;
import hxunity.prefab.UnityPrefab;
import hxunity.types.QuaternionData;
import hxunity.types.VectorData;
import hxunity.yaml.ClassIds;
import hxunity.yaml.Scalars;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.ScalarKind;

/** Tests for the high level prefab API. **/
class TestPrefab
{
	public static function run():Void
	{
		hierarchy();
		components();
		monoBehaviours();
		editing();
		creating();
		duplicating();
		removing();
		writing();
		strippedParents();
	}

	/** A two level prefab: Root, and Root/Child with a Transform and a renderer. */
	static function fixture():String
	{
		return [
			"%YAML 1.1",
			"%TAG !u! tag:unity3d.com,2011:",
			"--- !u!1 &100",
			"GameObject:",
			"  m_ObjectHideFlags: 0",
			"  m_Component:",
			"  - component: {fileID: 101}",
			"  m_Layer: 0",
			"  m_Name: Root",
			"  m_TagString: Untagged",
			"  m_IsActive: 1",
			"--- !u!4 &101",
			"Transform:",
			"  m_GameObject: {fileID: 100}",
			"  serializedVersion: 2",
			"  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}",
			"  m_LocalPosition: {x: 0, y: 0, z: 0}",
			"  m_LocalScale: {x: 1, y: 1, z: 1}",
			"  m_Children:",
			"  - {fileID: 201}",
			"  m_Father: {fileID: 0}",
			"  m_LocalEulerAnglesHint: {x: 0, y: 0, z: 0}",
			"--- !u!1 &200",
			"GameObject:",
			"  m_ObjectHideFlags: 0",
			"  m_Component:",
			"  - component: {fileID: 201}",
			"  - component: {fileID: 202}",
			"  m_Layer: 5",
			"  m_Name: Child",
			"  m_TagString: Player",
			"  m_IsActive: 0",
			"--- !u!4 &201",
			"Transform:",
			"  m_GameObject: {fileID: 200}",
			"  serializedVersion: 2",
			"  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}",
			"  m_LocalPosition: {x: 1.5, y: -2, z: 0}",
			"  m_LocalScale: {x: 1, y: 1, z: 1}",
			"  m_Children: []",
			"  m_Father: {fileID: 101}",
			"  m_LocalEulerAnglesHint: {x: 0, y: 0, z: 0}",
			"--- !u!23 &202",
			"MeshRenderer:",
			"  m_GameObject: {fileID: 200}",
			"  m_Enabled: 1",
			"  m_SortingOrder: 35",
			"--- !u!114 &203",
			"MonoBehaviour:",
			"  m_GameObject: {fileID: 200}",
			"  m_Enabled: 1",
			"  m_Script: {fileID: 11500000, guid: d247ba06193faa74d9335f5481b2b56c, type: 3}",
			"  m_Name: ",
			"  m_EditorClassIdentifier: ",
			"  speed: 3.5"
		].join("\n") + "\n";
	}

	static function hierarchy():Void
	{
		Assert.test("Prefab.hierarchy");
		var prefab = UnityPrefab.parse(fixture());
		Assert.equals(prefab.count(), 6, "six documents");

		var roots = prefab.rootGameObjects();
		Assert.equals(roots.length, 1, "one root GameObject");
		var root = roots[0];
		Assert.equals(root.name(), "Root", "root name");
		Assert.equals(root.depth(), 0, "root depth is 0");
		Assert.equals(root.parent(), null, "a root has no parent");
		// A root's `m_Father` is `{fileID: 0}`, so nothing is indexed under "0"
		// and the transform level accessor is null too.
		Assert.equals(root.transform().parentTransform(), null, "a root transform has no parent transform");

		var children = root.children();
		Assert.equals(children.length, 1, "one child");
		var child = children[0];
		Assert.equals(child.name(), "Child", "child name");
		Assert.equals(child.depth(), 1, "child depth is 1");
		Assert.equals(child.path(), "Root/Child", "hierarchy path");
		Assert.equals(child.parent().name(), "Root", "the child knows its parent");
		Assert.equals(child.layer(), 5, "m_Layer");
		Assert.equals(child.tag(), "Player", "m_TagString");
		Assert.isFalse(child.active(), "m_IsActive: 0 is false");
		Assert.isTrue(root.active(), "m_IsActive: 1 is true");

		Assert.equals(prefab.find("Child").name(), "Child", "find by name");
		Assert.equals(prefab.find("Missing"), null, "an unknown name is null");
		Assert.equals(prefab.findByPath("Root/Child").name(), "Child", "find by path");
		Assert.equals(prefab.findAll("Child").length, 1, "findAll by name");
		Assert.equals(prefab.allGameObjects().length, 2, "two GameObjects in total");
		Assert.equals(root.descendants().length, 1, "the root has one descendant");
		Assert.equals(root.find("Child"), child, "find inside a subtree");
	}

	static function components():Void
	{
		Assert.test("Prefab.components");
		var prefab = UnityPrefab.parse(fixture());
		var root = prefab.find("Root");
		Assert.equals(root.components().length, 1, "the root only has a transform");
		Assert.notNull(root.transform(), "the root transform is found");
		Assert.equals(root.getComponent(ClassIds.MeshRenderer), null, "the root has no renderer");

		var child = prefab.find("Child");
		Assert.equals(child.components().length, 2, "the child has a transform and a renderer");
		Assert.equals(child.components()[0].classId(), ClassIds.Transform, "the transform is listed first");
		var renderer = child.getComponent(ClassIds.MeshRenderer);
		Assert.notNull(renderer, "the renderer is found by class id");
		Assert.equals(renderer.className(), "MeshRenderer", "class name");
		Assert.equals(renderer.getInt("m_SortingOrder"), 35, "a field is readable");
		Assert.equals(renderer.gameObject().name(), "Child", "a component knows its GameObject");
		Assert.isTrue(renderer.enabled(), "m_Enabled");
		Assert.equals(idText(renderer.getReference("m_GameObject").fileId), "200", "the raw reference is available");

		Assert.equals(prefab.allComponentsOfType(ClassIds.MeshRenderer).length, 1, "search by class id");
		Assert.equals(prefab.allComponentsOfType(ClassIds.Transform).length, 2, "two transforms");
		Assert.equals(child.getComponents(ClassIds.Transform).length, 1, "getComponents on one object");
	}

	static function monoBehaviours():Void
	{
		Assert.test("Prefab.monoBehaviours");
		var prefab = UnityPrefab.parse(fixture());
		var behaviour = prefab.componentById(Int64.ofInt(203));
		Assert.notNull(behaviour, "the MonoBehaviour is wrapped");
		Assert.isTrue(Std.isOfType(behaviour, MonoBehaviourObject), "it gets the MonoBehaviour wrapper");
		var script:MonoBehaviourObject = cast behaviour;
		Assert.equals(script.scriptGuid(), "d247ba06193faa74d9335f5481b2b56c", "the script guid is read");
		Assert.equals(script.scriptReference().type, 3, "a project script uses type 3");
		Assert.equals(script.editorClassIdentifier(), "", "an empty editor class identifier stays empty");

		Assert.equals(script.resolveClassName(null), null, "the class name is unknown without an index");
		var index = new Map<String, String>();
		index.set("d247ba06193faa74d9335f5481b2b56c", "Spine.Unity.SkeletonAnimation");
		Assert.equals(script.resolveClassName(index), "Spine.Unity.SkeletonAnimation", "the class name resolves through a guid index");
		Assert.equals(script.getFloat("speed"), 3.5, "a serialised field on the behaviour is readable");
	}

	static function editing():Void
	{
		Assert.test("Prefab.editing");
		var prefab = UnityPrefab.parse(fixture());
		var child = prefab.find("Child");

		child.setName("Renamed");
		Assert.equals(prefab.find("Renamed").name(), "Renamed", "renaming is visible from the prefab");
		Assert.equals(prefab.find("Child"), null, "the old name is gone");

		child.setActive(true);
		Assert.isTrue(child.active(), "activation writes through");

		var transform = child.transform();
		transform.setLocalPosition(new VectorData(3, 4, 5));
		Assert.equals(transform.localPosition().x, 3.0, "position x");
		Assert.equals(transform.localPosition().y, 4.0, "position y");
		Assert.equals(transform.localPosition().z, 5.0, "position z");

		transform.setLocalScale(new VectorData(2, 2, 2));
		Assert.equals(transform.localScale().x, 2.0, "scale writes through");

		transform.setLocalRotation(new QuaternionData(0, 0.7071068, 0, 0.7071068));
		Assert.equals(transform.localRotation().y, 0.7071068, "rotation writes through");
		Assert.equals(transform.localRotation().w, 0.7071068, "rotation w");

		var renderer = child.getComponent(ClassIds.MeshRenderer);
		renderer.set("m_SortingOrder", Scalars.node(99));
		Assert.equals(renderer.getInt("m_SortingOrder"), 99, "an arbitrary field is writable");
		renderer.setEnabled(false);
		Assert.isFalse(renderer.enabled(), "a component can be disabled");
		Assert.notNull(renderer.removeField("m_SortingOrder"), "a field can be removed");
		Assert.isNull(renderer.get("m_SortingOrder"), "the removed field is gone");

		// Field order must survive edits so a written file still looks native.
		var emitted = prefab.emit();
		Assert.contains(emitted, "  m_Name: Renamed", "the edit is in the output");
		Assert.contains(emitted, "  m_LocalPosition: {x: 3, y: 4, z: 5}", "the vector edit is written in Unity's shape");
	}

	static function creating():Void
	{
		Assert.test("Prefab.creating");
		var prefab = UnityPrefab.parse(fixture());
		var before = prefab.count();

		var created = prefab.createGameObject("Extra");
		Assert.equals(prefab.count(), before + 2, "a GameObject and a Transform are added");
		Assert.equals(created.name(), "Extra", "the new object has its name");
		Assert.notNull(created.transform(), "the new object has a transform");
		Assert.equals(created.parent(), null, "it starts at the root");
		Assert.isTrue(created.active(), "Unity's default is active");
		Assert.equals(created.getComponent(ClassIds.Transform).classId(), ClassIds.Transform, "the transform is linked");

		Assert.equals(prefab.rootGameObjects().length, 2, "there are now two roots");

		var child = prefab.find("Root").addChild("Nested");
		Assert.equals(child.parent().name(), "Root", "addChild parents the object");
		Assert.contains(child.path(), "Root/Nested", "the path reflects the parent");
		Assert.equals(prefab.find("Root").children().length, 2, "the root lists both children");

		var renderer = child.addComponent("MeshRenderer");
		Assert.equals(renderer.classId(), ClassIds.MeshRenderer, "addComponent uses the class name");
		Assert.equals(child.components().length, 2, "the new component is linked to the object");
		Assert.equals(renderer.gameObject().name(), "Nested", "the new component points back at the object");

		var behaviour = child.addComponent("MonoBehaviour");
		Assert.isTrue(Std.isOfType(behaviour, MonoBehaviourObject), "addComponent returns the typed wrapper");
		Assert.equals(behaviour.gameObject().name(), "Nested", "the behaviour is attached");

		var error = Assert.throws(function()
		{
			child.addComponent("NotAUnityClass");
		}, "an unknown class name throws");
		Assert.contains(Std.string(error), "NotAUnityClass", "the error names the class");

		var second = prefab.createGameObject("Moved");
		second.setParent(prefab.find("Root"));
		Assert.equals(second.parent().name(), "Root", "setParent moves an object");
		Assert.equals(prefab.rootGameObjects().length, 2, "moving removes it from the roots");
		second.setParent(null);
		Assert.equals(second.parent(), null, "setParent(null) moves it back to the root");
		Assert.equals(prefab.rootGameObjects().length, 3, "it is a root again");

		// Reordering changes the order Unity draws the children in.
		var rootChildren = prefab.find("Root").children();
		var firstName = rootChildren[0].name();
		rootChildren[0].transform().setSiblingIndex(1);
		Assert.equals(prefab.find("Root").children()[1].name(), firstName, "setSiblingIndex reorders m_Children");
	}

	static function duplicating():Void
	{
		Assert.test("Prefab.duplicating");
		var prefab = UnityPrefab.parse(fixture());
		var source = prefab.find("Child");
		var before = prefab.count();

		var clone = prefab.duplicate(source);
		Assert.notNull(clone, "the clone exists");
		Assert.equals(prefab.count(), before + 3, "the clone adds a GameObject, a Transform and a renderer");
		Assert.equals(clone.name(), "Child", "the clone keeps the name");
		Assert.notNull(clone.transform(), "the clone has a transform");
		Assert.equals(childCount(prefab, "Root"), 2, "the clone is a second child of the original parent");
		Assert.isFalse(clone.fileId() == source.fileId(), "the clone has a fresh file id");

		// The clone's internal references must point at the clone, not the original.
		var cloneTransform = clone.transform();
		Assert.equals(idText(cloneTransform.gameObject().fileId()), idText(clone.fileId()), "the clone transform points at the clone");
		var renderer = clone.getComponent(ClassIds.MeshRenderer);
		Assert.notNull(renderer, "the clone kept the renderer");
		Assert.equals(idText(renderer.gameObject().fileId()), idText(clone.fileId()), "the clone renderer points at the clone");
		Assert.isFalse(idText(renderer.getReference("m_GameObject").fileId) == idText(source.fileId()),
			"the clone does not reference the original");

		// Editing the clone must not touch the original.
		clone.setName("Clone");
		Assert.equals(source.name(), "Child", "the original is untouched");
		cloneTransform.setLocalPosition(new VectorData(9, 9, 9));
		Assert.equals(source.transform().localPosition().x, 1.5, "the original position is untouched");

		var nested = prefab.duplicate(prefab.find("Root"), null);
		Assert.notNull(nested, "a subtree clone exists");
		Assert.equals(nested.name(), "Root", "the subtree clone keeps the root name");
		Assert.equals(nested.children().length, 2, "the whole subtree was duplicated");
	}

	/**
		A prefab instance: the child's transform lists a parent that Unity wrote as
		a `stripped` transform. That document is indexed but has no `m_GameObject`,
		so it must not make the child disappear from the root list.
	**/
	static function strippedParentFixture():String
	{
		return [
			"%YAML 1.1",
			"%TAG !u! tag:unity3d.com,2011:",
			"--- !u!1 &100",
			"GameObject:",
			"  m_Component:",
			"  - component: {fileID: 101}",
			"  m_Name: Child",
			"  m_IsActive: 1",
			"--- !u!4 &101",
			"Transform:",
			"  m_GameObject: {fileID: 100}",
			"  m_Children: []",
			"  m_Father: {fileID: 201}",
			"--- !u!4 &201 stripped",
			"Transform:",
			"  m_CorrespondingSourceObject: {fileID: 111, guid: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, type: 3}",
			"  m_PrefabInstance: {fileID: 999}",
			"  m_PrefabAsset: {fileID: 0}"
		].join("\n") + "\n";
	}

	static function strippedParents():Void
	{
		Assert.test("Prefab.strippedParents");
		var prefab = UnityPrefab.parse(strippedParentFixture());
		Assert.equals(prefab.count(), 3, "the stripped parent is a third document");

		var child = prefab.find("Child");
		Assert.notNull(child, "the child is found");

		var transform = child.transform();
		var parentTransform = transform.parentTransform();
		// The document really is there, so the transform level accessor reports it.
		Assert.notNull(parentTransform, "m_Father names an existing document, so parentTransform is not null");
		Assert.isTrue(parentTransform.isStripped(), "the referenced parent is the stripped document");
		// ...but it has no GameObject here, which is the case that used to be
		// mistaken for "this object has a parent".
		Assert.equals(parentTransform.gameObject(), null, "a stripped transform has no GameObject in this file");
		Assert.equals(transform.parent(), null, "parent() reports no parent in this file");
		Assert.equals(child.parent(), null, "and neither does the GameObject");

		// The regression: the child used to vanish from both the parent list and
		// the root list, leaving it reachable only through allGameObjects().
		Assert.equals(prefab.allGameObjects().length, 1, "one GameObject exists");
		Assert.equals(prefab.rootGameObjects().length, 1, "an unresolvable parent must not hide the object from the roots");
		Assert.equals(prefab.rootGameObjects()[0].name(), "Child", "the child is the root");
		Assert.equals(child.depth(), 0, "an object with no representable parent has depth 0");
	}

	static function childCount(prefab:UnityPrefab, parentName:String):Int
	{
		var parent = prefab.find(parentName);
		return parent == null ? -1 : parent.children().length;
	}

	/** An id as text, for assertions that do not want to compare Int64 values. **/
	static function idText(id:haxe.Int64):String
	{
		return hxunity.unity.FileId.toStr(id);
	}

	static function removing():Void
	{
		Assert.test("Prefab.removing");
		var prefab = UnityPrefab.parse(fixture());
		var child = prefab.find("Child");
		var before = prefab.count();

		child.remove();
		Assert.equals(prefab.count(), before - 3, "the GameObject, its transform and its renderer are removed");
		Assert.equals(prefab.find("Child"), null, "the object is gone");
		Assert.equals(prefab.find("Root").children().length, 0, "the parent no longer lists it");
		Assert.equals(prefab.find("Root").transform().childTransforms().length, 0, "m_Children is empty");

		// Removing the root removes the whole subtree.
		var prefab2 = UnityPrefab.parse(fixture());
		prefab2.find("Root").remove();
		Assert.equals(prefab2.allGameObjects().length, 0, "removing the root removes its descendants too");
		Assert.equals(prefab2.rootGameObjects().length, 0, "nothing is left at the root");

		// Removing a single component leaves the GameObject alone.
		var prefab3 = UnityPrefab.parse(fixture());
		var renderer = prefab3.find("Child").getComponent(ClassIds.MeshRenderer);
		var countBefore = prefab3.count();
		renderer.remove();
		Assert.equals(prefab3.count(), countBefore - 1, "only the component document is removed");
		Assert.equals(prefab3.find("Child").getComponent(ClassIds.MeshRenderer), null, "the component is detached");
		Assert.notNull(prefab3.find("Child"), "the GameObject remains");
	}

	static function writing():Void
	{
		Assert.test("Prefab.writing");
		var prefab = UnityPrefab.parse(fixture());
		// An unmodified prefab must be written back byte for byte.
		Assert.stringEquals(prefab.emit(), fixture(), "an untouched prefab round trips through the API");

		prefab.find("Child").setName("Modified");
		var emitted = prefab.emit();
		var reparsed = UnityPrefab.parse(emitted);
		Assert.equals(reparsed.find("Modified").name(), "Modified", "the written file re-reads with the change");
		Assert.equals(reparsed.count(), prefab.count(), "the document count is stable");
		Assert.equals(reparsed.find("Child"), null, "the old name is not in the written file");
		Assert.equals(reparsed.find("Root").children()[0].name(), "Modified", "the hierarchy survives a write and read");

		var file = "build/test-prefab.prefab";
		FileSystem.createDirectory("build");
		prefab.save(file);
		Assert.isTrue(FileSystem.exists(file), "the file was written");
		var loaded = UnityPrefab.fromFile(file);
		Assert.equals(loaded.path, file, "the loader records its path");
		Assert.equals(loaded.find("Modified").name(), "Modified", "the saved file loads back");
		loaded.save();
		Assert.stringEquals(sys.io.File.getContent(file), emitted, "saving without changes is a no-op");
		FileSystem.deleteFile(file);
		var empty = UnityPrefab.createEmpty();
		Assert.equals(empty.count(), 0, "a new prefab has no documents");
		var root = empty.createGameObject("Only");
		Assert.equals(empty.count(), 2, "adding an object creates two documents");
		Assert.contains(empty.emit(), "%YAML 1.1", "the preamble is written for a new prefab");
		Assert.contains(empty.emit(), "--- !u!1 &", "the object gets a header");
		Assert.contains(empty.emit(), "  m_Name: Only", "the object's name is written");
		Assert.equals(UnityPrefab.parse(empty.emit()).find("Only").name(), "Only", "the new prefab reads back");
	}
}
