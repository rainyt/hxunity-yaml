package hxunity.prefab;

import hxunity.unity.AssetGuidIndex;

/**
	同一工程内按 guid 共享的源预制体缓存。

	场景里同一份 .prefab 常被多个 PrefabInstance 引用；没有缓存时每个实例都
	各自从磁盘读文件、各建一棵对象图。缓存按 `guid + 文件 mtime` 判定有效性：
	文件被写回（例如 [PrefabInstance.applyToPrefab]）后 mtime 变化，下一次
	[get] 自动重新加载，不需要手工失效。

	缓存直接持有共享的对象图，调用方**不得修改** [get] 返回的实例——需要改动
	时用 `UnityPrefab.deepClone()`（[PrefabInstance.effectivePrefab] 内部就是
	这样做的）。跨多个场景或多次 list 调用时可以显式传入同一个缓存实例。
**/
class PrefabSourceCache
{
	/** 实际从磁盘加载过的次数，用于确认命中率与测试。 **/
	public var loads(default, null):Int;

	var entries:Map<String, {mtime:Float, prefab:UnityPrefab}>;

	public function new()
	{
		loads = 0;
		entries = new Map();
	}

	/**
		guid 指向的源预制体，优先命中缓存。

		mtime 不一致（文件被外部或本库写回）时重新加载并替换缓存条目；索引解析
		不到或文件读取失败返回 `null`，不缓存失败结果。
	**/
	public function get(index:AssetGuidIndex, guid:String):UnityPrefab
	{
		if (index == null || guid == null) return null;
		var key = guid.toLowerCase();
		var absolute = index.absolutePathOf(guid);
		if (absolute == null) return null;
		var mtime = mtimeOf(absolute);
		if (mtime < 0) return null;
		var entry = entries.get(key);
		if (entry != null && entry.mtime == mtime) return entry.prefab;
		var prefab:UnityPrefab = null;
		try
		{
			prefab = UnityPrefab.fromFile(absolute);
		}
		catch (e:Dynamic)
		{
			return null;
		}
		loads++;
		entries.set(key, {mtime: mtime, prefab: prefab});
		return prefab;
	}

	/**
		把一个刚从磁盘加载（或刚写回）的 prefab 放进缓存，按当前 mtime 登记。

		[PrefabInstance.applyToPrefab] 写回后调用它，让后续 [get] 直接看到
		写回后的内容而无需再读盘。
	**/
	public function put(index:AssetGuidIndex, guid:String, prefab:UnityPrefab):Void
	{
		if (index == null || guid == null || prefab == null || prefab.path == null) return;
		var mtime = mtimeOf(prefab.path);
		if (mtime < 0) return;
		entries.set(guid.toLowerCase(), {mtime: mtime, prefab: prefab});
	}

	/** 丢弃全部缓存条目。 **/
	public function clear():Void
	{
		entries = new Map();
	}

	function mtimeOf(path:String):Float
	{
		try
		{
			return sys.FileSystem.stat(path).mtime.getTime();
		}
		catch (e:Dynamic)
		{
			return -1;
		}
	}
}
