package;

import haxe.Int64;
import hxunity.unity.AssetGuidIndex;
import hxunity.unity.AssetKind;
import hxunity.unity.Origin;
import hxunity.unity.UnityReference;
import hxunity.prefab.PrefabInstance;
import hxunity.prefab.PrefabSourceCache;
import hxunity.prefab.UnityPrefab;

/**
	 prefab 实例层的端到端测试：临时目录里搭一个最小 Unity 工程
	（一个 .prefab + 一个 .meta + 一个引用它的 .unity），走一遍
	"加载视图 → 场景覆盖 → Apply 写回预制体"的完整流程。
**/
class TestPrefabInstance
{
	static var root:String;

	public static function run():Void
	{
		Assert.test("PrefabInstance.workflow");
		root = "build/test-prefabinstance";
		writeFixture();

		var index = new AssetGuidIndex(root);
		index.addEntry(PREFAB_GUID, "Assets/Prefabs/Hero.prefab", AssetKind.Prefab, Origin.Project, Int64.ofInt(100100000));

		var scene = UnityPrefab.fromFile(root + "/Assets/Scenes/Main.unity");
		var instances = PrefabInstance.list(scene, index);
		Assert.equals(instances.length, 1, "one prefab instance in the scene");
		var instance = instances[0];

		Assert.equals(instance.sourceGuid(), PREFAB_GUID, "source guid");
		Assert.equals(instance.sourcePath(), "Assets/Prefabs/Hero.prefab", "guid resolved to the prefab path");
		Assert.isFalse(instance.isMissing(), "the source prefab resolves");

		// 视图：源预制体 + 场景覆盖
		var view = instance.effectivePrefab();
		Assert.notNull(view, "the effective prefab loads");
		var rootObject = instance.rootGameObject();
		Assert.notNull(rootObject, "the instance root exists");
		Assert.equals(rootObject.name(), "Hero_Renamed", "the m_Name override is applied");
		Assert.equals(rootObject.transform().localPosition().x, 1.5, "the m_LocalPosition.x override is applied");
		Assert.equals(rootObject.transform().localPosition().y, 0.0, "fields without overrides keep prefab values");
		var hand = view.findByPath("Hero_Renamed/Hand");
		Assert.notNull(hand, "the prefab's full hierarchy is in the view");
		Assert.equals(hand.name(), "Hand", "the child keeps its prefab name");
		Assert.equals(instance.modificationCount(), 3, "three overrides from the fixture");

		// 共享缓存：同 guid 只从磁盘加载一次，视图互不影响
		var cache = new PrefabSourceCache();
		var listA = PrefabInstance.list(scene, index, cache);
		var listB = PrefabInstance.list(scene, index, cache);
		Assert.equals(listA[0].sourcePrefab(), listB[0].sourcePrefab(), "the cached source graph is shared");
		Assert.equals(cache.loads, 1, "one shared guid loads once");
		var firstView = listA[0].effectivePrefab();
		firstView.find("Hero_Renamed").setName("Touched");
		Assert.equals(listB[0].effectivePrefab().findByPath("Hero_Renamed").name(), "Hero_Renamed",
			"mutating one view leaves later views untouched");
		Assert.equals(listA[0].sourcePrefab().rootGameObjects()[0].name(), "Hero",
			"the shared source itself is never mutated by views");

		// 场景覆盖：更新已有条目是就地更新，不新增
		var before = instance.modificationCount();
		instance.setOverride(Int64.ofInt(101), "m_LocalPosition.x", "9.25");
		Assert.equals(instance.modificationCount(), before, "rewriting the same path updates in place");
		Assert.equals(instance.effectivePrefab().findByPath("Hero_Renamed").transform().localPosition().x, 9.25,
			"the view reflects the new override");

		// 新增一条覆盖 → 落进场景的 m_Modifications，视图可见
		instance.setOverride(Int64.ofInt(102), "m_Name", "Hand_Tweaked");
		Assert.equals(instance.effectivePrefab().findByPath("Hero_Renamed/Hand_Tweaked").name(), "Hand_Tweaked",
			"an override on a child object lands in the view");

		// 场景保存后重载，覆盖仍在
		scene.save();
		var reloaded = UnityPrefab.fromFile(root + "/Assets/Scenes/Main.unity");
		var reloadedInstance = PrefabInstance.list(reloaded, index)[0];
		Assert.equals(reloadedInstance.modificationCount(), 4, "the override was written into the scene document");
		Assert.equals(reloadedInstance.effectivePrefab().findByPath("Hero_Renamed/Hand_Tweaked").name(), "Hand_Tweaked",
			"the override survives a save/reload cycle");

		// 引用覆盖：{fileID: 0} 表示置空，实例内的 Hand 脱离父级成为根
		instance.setObjectReferenceOverride(Int64.ofInt(103), "m_Father", UnityReference.none().toNode());
		var detached = instance.effectivePrefab().find("Hand_Tweaked");
		Assert.equals(detached.transform().parentTransform(), null,
			"a zero reference override clears the field");

		// Apply：覆盖写进 .prefab 文件；场景文件的覆盖保留
		var result = instance.applyToPrefab();
		Assert.equals(result.applied, 5, "all applicable overrides applied");
		Assert.equals(result.skippedSceneReferences, 0, "no scene references to skip in the fixture");
		var appliedPrefab = UnityPrefab.fromFile(root + "/Assets/Prefabs/Hero.prefab");
		Assert.equals(appliedPrefab.find("Hero_Renamed") != null, true, "the applied name is in the prefab file");
		Assert.equals(appliedPrefab.findByPath("Hero_Renamed").transform().localPosition().x, 9.25,
			"the applied position is in the prefab file");
		var onDisk = sys.io.File.getContent(root + "/Assets/Scenes/Main.unity");
		Assert.contains(onDisk, "m_Name", "the scene file keeps its modifications after apply");

		// Apply 后缓存自动失效并持有写回后的内容（mtime 变化触发）
		var afterApply = PrefabInstance.list(scene, index, cache);
		Assert.equals(cache.loads, 1, "no reload needed after apply: put() refreshed the entry");
		Assert.equals(afterApply[0].sourcePrefab().rootGameObjects()[0].name(), "Hero_Renamed",
			"the cache serves the post-apply content");

		// Revert 单项与全部
		Assert.isTrue(instance.removeOverride(Int64.ofInt(101), "m_LocalPosition.x"), "the override is removed");
		Assert.equals(instance.effectivePrefab().findByPath("Hero_Renamed").transform().localPosition().x, 9.25,
			"without the override the view shows the (now applied) prefab value");
		instance.clearOverrides();
		Assert.equals(instance.modificationCount(), 0, "clearOverrides empties m_Modifications");

		// 缺失源资产：guid 在索引与磁盘上都找不到
		var missingScene = UnityPrefab.parse(lines([
			"%YAML 1.1",
			"%TAG !u! tag:unity3d.com,2011:",
			"--- !u!1001 &901",
			"PrefabInstance:",
			"  m_ObjectHideFlags: 0",
			"  serializedVersion: 2",
			"  m_Modification:",
			"    serializedVersion: 3",
			"    m_TransformParent: {fileID: 0}",
			"    m_Modifications: []",
			"    m_RemovedGameObjects: []",
			"    m_RemovedComponents: []",
			"  m_SourcePrefab: {fileID: 100100000, guid: deadbeef000000000000000000000000, type: 3}"
		]));
		var missing = PrefabInstance.list(missingScene, index)[0];
		Assert.isTrue(missing.isMissing(), "an unresolvable guid is missing");
		Assert.isNull(missing.effectivePrefab(), "a missing source has no view");
	}

	static inline var PREFAB_GUID = "c0ffee0000000000000000000000abcd";

	static inline var GROUP_GUID = "cafebabel000000000000000000000123";

	/**
		createPrefabInstance 的端到端测试：临时工程里建一个源组预制体和一个宿主
		prefab（含挂载父对象），创建 → 便利覆盖 → 落盘 → 重读断言（需求单验收
		标准 1–4），并断言 parentTransformFileId / parentGameObject 的嵌套读取
		（需求 3）。
	**/
	public static function runCreate():Void
	{
		Assert.test("PrefabInstance.create");
		root = "build/test-prefabinstance-create";
		writeCreateFixture();

		var index = new AssetGuidIndex(root);
		index.addEntry(GROUP_GUID, "Assets/Prefabs/Group.prefab", AssetKind.Prefab, Origin.Project, Int64.ofInt(100100000));

		var host = UnityPrefab.fromFile(root + "/Assets/Prefabs/Host.prefab");
		var hostRoot = host.find("HostRoot");
		Assert.notNull(hostRoot, "the host prefab loads with its root object");

		// 两个实例挂在 HostRoot 下：占位进入 m_Children 的顺序 = 创建顺序
		var first = host.createPrefabInstance(GROUP_GUID, Int64.ofInt(100), Int64.ofInt(101), hostRoot);
		first.setInstanceName("safa");
		first.setInstancePlacement(1.5, 2.5, 0, 0, 0, 0, 1);
		var second = host.createPrefabInstance(GROUP_GUID, Int64.ofInt(100), Int64.ofInt(101), hostRoot);
		second.setInstanceName("safa2");
		second.setInstancePlacement(3, 4, 0, 0, 0, 0, 1);

		// 创建后（落盘前）：8 条覆盖已就位；无 index 时视图为 null 是文档写明的预期
		Assert.equals(first.modificationCount(), 8, "name + 7 placement scalars are recorded as overrides");
		Assert.isNull(first.effectivePrefab(), "effectivePrefab is null without an index before save, as documented");
		Assert.notNull(first.instanceTransform(), "the placeholder is reachable before save");

		host.save();

		// 验收 4：落盘头部为实例头 + stripped 头
		var onDisk = sys.io.File.getContent(root + "/Assets/Prefabs/Host.prefab");
		var placeholder = first.instanceTransform();
		Assert.contains(onDisk, '--- !u!1001 &${first.document().fileIdText()}', "the instance document keeps its header");
		Assert.contains(onDisk, '--- !u!4 &${placeholder.document.fileIdText()} stripped', "the placeholder keeps its stripped header");

		// 验收 1：重读后恰好列出创建的实例，sourceGuid 正确
		var reloaded = UnityPrefab.fromFile(root + "/Assets/Prefabs/Host.prefab");
		var instances = PrefabInstance.list(reloaded, index);
		Assert.equals(instances.length, 2, "exactly the created instances are listed after a reload");
		Assert.equals(instances[0].sourceGuid(), GROUP_GUID, "the first instance's source guid");
		Assert.isFalse(instances[0].isMissing(), "the source resolves through the guid index");

		// 需求 3：m_TransformParent 从 m_Modification 下读取
		Assert.stringEquals(Int64.toStr(instances[0].parentTransformFileId()), "201", "the parent transform is read from the nested m_Modification path");
		Assert.equals(instances[0].parentGameObject().name(), "HostRoot", "the parent GameObject resolves through the nested path");

		// 验收 2：视图应用覆盖后的名字与 TRS
		var rootObject = instances[0].rootGameObject();
		Assert.equals(rootObject.name(), "safa", "the m_Name override is applied to the view root");
		Assert.equals(rootObject.transform().localPosition().x, 1.5, "the m_LocalPosition.x override is applied");
		Assert.equals(rootObject.transform().localPosition().y, 2.5, "the m_LocalPosition.y override is applied");
		Assert.equals(rootObject.transform().localRotation().w, 1, "the m_LocalRotation.w override is applied");
		Assert.equals(rootObject.transform().localRotation().x, 0, "the m_LocalRotation.x override is applied");

		// 验收 3：父 Transform 的 m_Children 含两个占位且按创建顺序
		var reloadedHostRoot = reloaded.find("HostRoot");
		var children = reloadedHostRoot.transform().childTransforms();
		Assert.equals(children.length, 2, "both placeholders hang under the parent transform");
		Assert.stringEquals(children[0].document.fileIdText(), placeholder.document.fileIdText(), "the first placeholder keeps creation order");
		Assert.stringEquals(children[1].document.fileIdText(), second.instanceTransform().document.fileIdText(),
			"the second placeholder keeps creation order");

		// 验收 3：占位反查与回指
		var reloadedPlaceholder = instances[0].instanceTransform();
		Assert.notNull(reloadedPlaceholder, "the placeholder is found by instanceTransform after reload");
		Assert.isNull(reloadedPlaceholder.gameObject(), "the placeholder has no GameObject of its own");
		var backReference = UnityReference.fromNode(reloadedPlaceholder.get("m_PrefabInstance"));
		Assert.stringEquals(backReference.fileIdText(), instances[0].document().fileIdText(),
			"the placeholder's m_PrefabInstance points back at the instance document");

		// 从磁盘加载的实例没有登记源根 fileID：便利方法必须拒绝而不是猜
		Assert.throws(function() instances[0].setInstanceName("x"), "setInstanceName on a loaded instance throws");
		Assert.throws(function() instances[0].setInstancePlacement(0, 0, 0, 0, 0, 0, 1), "setInstancePlacement on a loaded instance throws");
	}

	/** 源组预制体 + 宿主 prefab（根对象 HostRoot），均为手写 Unity 格式。 **/
	static function writeCreateFixture():Void
	{
		deleteTree(root);
		sys.FileSystem.createDirectory(root + "/Assets/Prefabs");

		sys.io.File.saveContent(root + "/Assets/Prefabs/Group.prefab", lines([
			"%YAML 1.1",
			"%TAG !u! tag:unity3d.com,2011:",
			"--- !u!1 &100",
			"GameObject:",
			"  m_ObjectHideFlags: 0",
			"  m_CorrespondingSourceObject: {fileID: 0}",
			"  m_PrefabInstance: {fileID: 0}",
			"  m_PrefabAsset: {fileID: 0}",
			"  m_GameObject: {fileID: 100}",
			"  m_Enabled: 1",
			"  serializedVersion: 6",
			"  m_Component:",
			"  - component: {fileID: 101}",
			"  m_Name: GroupRoot",
			"  m_TagString: Untagged",
			"  m_Layer: 0",
			"--- !u!4 &101",
			"Transform:",
			"  m_ObjectHideFlags: 0",
			"  m_CorrespondingSourceObject: {fileID: 0}",
			"  m_GameObject: {fileID: 100}",
			"  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}",
			"  m_LocalPosition: {x: 0, y: 0, z: 0}",
			"  m_LocalScale: {x: 1, y: 1, z: 1}",
			"  m_Children:",
			"  - {fileID: 103}",
			"  m_Father: {fileID: 0}",
			"--- !u!1 &102",
			"GameObject:",
			"  m_ObjectHideFlags: 0",
			"  m_CorrespondingSourceObject: {fileID: 0}",
			"  m_PrefabInstance: {fileID: 0}",
			"  m_PrefabAsset: {fileID: 0}",
			"  m_GameObject: {fileID: 102}",
			"  m_Enabled: 1",
			"  serializedVersion: 6",
			"  m_Component:",
			"  - component: {fileID: 103}",
			"  m_Name: Piece",
			"  m_TagString: Untagged",
			"  m_Layer: 0",
			"--- !u!4 &103",
			"Transform:",
			"  m_ObjectHideFlags: 0",
			"  m_CorrespondingSourceObject: {fileID: 0}",
			"  m_GameObject: {fileID: 102}",
			"  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}",
			"  m_LocalPosition: {x: 0.3, y: 0, z: 0}",
			"  m_LocalScale: {x: 1, y: 1, z: 1}",
			"  m_Children: []",
			"  m_Father: {fileID: 101}"
		]));
		sys.io.File.saveContent(root + "/Assets/Prefabs/Group.prefab.meta", lines([
			"fileFormatVersion: 2",
			'guid: $GROUP_GUID',
			"PrefabImporter:",
			"  externalObjects: {}",
			"  userData:",
			"  assetBundleName:",
			"  assetBundleVariant:"
		]));

		sys.io.File.saveContent(root + "/Assets/Prefabs/Host.prefab", lines([
			"%YAML 1.1",
			"%TAG !u! tag:unity3d.com,2011:",
			"--- !u!1 &200",
			"GameObject:",
			"  m_ObjectHideFlags: 0",
			"  m_CorrespondingSourceObject: {fileID: 0}",
			"  m_PrefabInstance: {fileID: 0}",
			"  m_PrefabAsset: {fileID: 0}",
			"  m_GameObject: {fileID: 200}",
			"  m_Enabled: 1",
			"  serializedVersion: 6",
			"  m_Component:",
			"  - component: {fileID: 201}",
			"  m_Name: HostRoot",
			"  m_TagString: Untagged",
			"  m_Layer: 0",
			"--- !u!4 &201",
			"Transform:",
			"  m_ObjectHideFlags: 0",
			"  m_CorrespondingSourceObject: {fileID: 0}",
			"  m_GameObject: {fileID: 200}",
			"  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}",
			"  m_LocalPosition: {x: 0, y: 0, z: 0}",
			"  m_LocalScale: {x: 1, y: 1, z: 1}",
			"  m_Children: []",
			"  m_Father: {fileID: 0}"
		]));
	}

	static function writeFixture():Void
	{
		deleteTree(root);
		sys.FileSystem.createDirectory(root + "/Assets/Prefabs");
		sys.FileSystem.createDirectory(root + "/Assets/Scenes");

		var prefab = lines([
			"%YAML 1.1",
			"%TAG !u! tag:unity3d.com,2011:",
			"--- !u!1 &100",
			"GameObject:",
			"  m_ObjectHideFlags: 0",
			"  m_CorrespondingSourceObject: {fileID: 0}",
			"  m_PrefabInstance: {fileID: 0}",
			"  m_PrefabAsset: {fileID: 0}",
			"  m_GameObject: {fileID: 100}",
			"  m_Enabled: 1",
			"  serializedVersion: 6",
			"  m_Component:",
			"  - component: {fileID: 101}",
			"  m_Name: Hero",
			"  m_TagString: Untagged",
			"  m_Layer: 0",
			"--- !u!4 &101",
			"Transform:",
			"  m_ObjectHideFlags: 0",
			"  m_CorrespondingSourceObject: {fileID: 0}",
			"  m_GameObject: {fileID: 100}",
			"  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}",
			"  m_LocalPosition: {x: 0, y: 0, z: 0}",
			"  m_LocalScale: {x: 1, y: 1, z: 1}",
			"  m_Children:",
			"  - {fileID: 103}",
			"  m_Father: {fileID: 0}",
			"--- !u!1 &102",
			"GameObject:",
			"  m_ObjectHideFlags: 0",
			"  m_CorrespondingSourceObject: {fileID: 0}",
			"  m_PrefabInstance: {fileID: 0}",
			"  m_PrefabAsset: {fileID: 0}",
			"  m_GameObject: {fileID: 102}",
			"  m_Enabled: 1",
			"  serializedVersion: 6",
			"  m_Component:",
			"  - component: {fileID: 103}",
			"  m_Name: Hand",
			"  m_TagString: Untagged",
			"  m_Layer: 0",
			"--- !u!4 &103",
			"Transform:",
			"  m_ObjectHideFlags: 0",
			"  m_CorrespondingSourceObject: {fileID: 0}",
			"  m_GameObject: {fileID: 102}",
			"  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}",
			"  m_LocalPosition: {x: 0.3, y: 0, z: 0}",
			"  m_LocalScale: {x: 1, y: 1, z: 1}",
			"  m_Children: []",
			"  m_Father: {fileID: 101}"
		]);
		sys.io.File.saveContent(root + "/Assets/Prefabs/Hero.prefab", prefab);
		sys.io.File.saveContent(root + "/Assets/Prefabs/Hero.prefab.meta", lines([
			"fileFormatVersion: 2",
			'guid: $PREFAB_GUID',
			"PrefabImporter:",
			"  externalObjects: {}",
			"  userData:",
			"  assetBundleName:",
			"  assetBundleVariant:"
		]));

		var scene = lines([
			"%YAML 1.1",
			"%TAG !u! tag:unity3d.com,2011:",
			"--- !u!1001 &900",
			"PrefabInstance:",
			"  m_ObjectHideFlags: 0",
			"  serializedVersion: 2",
			"  m_Modification:",
			"    serializedVersion: 3",
			"    m_TransformParent: {fileID: 0}",
			"    m_Modifications:",
			'    - target: {fileID: 100, guid: $PREFAB_GUID, type: 3}',
			"      propertyPath: m_Name",
			"      value: Hero_Renamed",
			'    - target: {fileID: 101, guid: $PREFAB_GUID, type: 3}',
			"      propertyPath: m_LocalPosition.x",
			"      value: 1.5",
			'    - target: {fileID: 101, guid: $PREFAB_GUID, type: 3}',
			"      propertyPath: m_LocalEulerAnglesHint.y",
			"      value: 45",
			"    m_RemovedGameObjects: []",
			"    m_RemovedComponents: []",
			'  m_SourcePrefab: {fileID: 100100000, guid: $PREFAB_GUID, type: 3}'
		]);
		sys.io.File.saveContent(root + "/Assets/Scenes/Main.unity", scene);
	}

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
		}
		else
		{
			sys.FileSystem.deleteFile(path);
		}
	}

	static function lines(parts:Array<String>):String
	{
		return parts.join("\n") + "\n";
	}
}
