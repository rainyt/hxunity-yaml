package;

import hxunity.unity.AssetGuidIndex;
import hxunity.unity.AssetKind;
import hxunity.unity.BuiltinResources;
import hxunity.unity.CachedGuidIndex;
import hxunity.unity.MetaFile;
import hxunity.unity.Origin;
import hxunity.unity.RefreshResult;
import hxunity.unity.UnityReference;
import haxe.Int64;

/**
	Tests for the GUID index and its cache.

	The cache tests build a throwaway project under `build/` and modify it, so the
	assertions cover the cases that matter for correctness: an added file, a deleted
	file, an added directory, a deleted directory, and an in-place edit that must
	*not* invalidate anything.
**/
class TestGuidIndex
{
	/** Project the cache tests build and then delete. **/
	static var root = "build/guid-test-project";

	/** Cache file, deliberately outside the project so it is never scanned. **/
	static var cacheFile = "build/guid-test-cache.tsv";

	public static function run():Void
	{
		metaParsing();
		builtins();
		handBuiltIndex();
		resolution();
		cache(true);
	}

	// ------------------------------------------------------------------- parsing

	static function metaParsing():Void
	{
		Assert.test("GuidIndex.metaParsing");

		var native = MetaFile.parse("fileFormatVersion: 2\nguid: AABBCCDDEEFF00112233445566778899\nNativeFormatImporter:\n  externalObjects: {}\n  mainObjectFileID: 2100000\n");
		Assert.equals(native.guid, "aabbccddeeff00112233445566778899", "the guid is lowercased");
		Assert.equals(native.importer, "NativeFormatImporter", "the importer section is read");
		Assert.equals(Int64.toStr(native.mainObjectFileId), "2100000", "mainObjectFileID is read");
		Assert.isFalse(native.isFolder, "a material is not a folder");

		// A `labels:` key can precede the importer section, so the first top level key
		// is not necessarily the importer.
		var labelled = MetaFile.parse("fileFormatVersion: 2\nguid: aaaa0000000000000000000000000000\nlabels:\n- one\n- two\nTextureImporter:\n  mipmaps:\n    enableMipMap: 0\n");
		Assert.equals(labelled.importer, "TextureImporter", "labels does not shadow the importer");

		// A nested key of the same name must not be picked up as the importer's own.
		var nested = MetaFile.parse("fileFormatVersion: 2\nguid: bbbb0000000000000000000000000000\nTextureImporter:\n  mipmaps:\n    mainObjectFileID: 999\n");
		Assert.equals(nested.mainObjectFileId, null, "a nested mainObjectFileID is ignored");

		var folder = MetaFile.parse("fileFormatVersion: 2\nguid: cccc0000000000000000000000000000\nfolderAsset: yes\nDefaultImporter:\n  userData: \n");
		Assert.isTrue(folder.isFolder, "folderAsset: yes is recognised");
		Assert.equals(folder.importer, "DefaultImporter", "the folder importer is read");

		// A file this does not understand must yield nulls rather than throwing.
		var empty = MetaFile.parse("");
		Assert.equals(empty.guid, null, "empty input yields no guid");
		Assert.equals(empty.importer, null, "empty input yields no importer");
	}

	// ------------------------------------------------------------------ builtins

	static function builtins():Void
	{
		Assert.test("GuidIndex.builtins");

		// Observed in a real project: built-in references use these two guids, and
		// neither of them is the all-zero guid.
		Assert.isTrue(BuiltinResources.isBuiltinGuid("0000000000000000e000000000000000"), "the e0 built-in guid is recognised");
		Assert.isTrue(BuiltinResources.isBuiltinGuid("0000000000000000f000000000000000"), "the f0 built-in guid is recognised");
		Assert.isFalse(BuiltinResources.isBuiltinGuid("00000000000000000000000000000000"), "the all-zero guid is not a built-in asset");
		Assert.isFalse(BuiltinResources.isBuiltinGuid("506c261dd94da1d4c93293b19207e8b0"), "a project guid is not built-in");
		Assert.isFalse(BuiltinResources.isBuiltinGuid(null), "null is not built-in");

		Assert.equals(BuiltinResources.nameOf(Int64.ofInt(10210)), "Cube", "the one confirmed name is known");
		Assert.equals(BuiltinResources.nameOf(Int64.ofInt(10754)), null, "an unnamed built-in id has no name rather than a guess");
		Assert.isTrue(BuiltinResources.isObjectId(Int64.ofInt(1)), "a real id is an object id");
		Assert.isFalse(BuiltinResources.isObjectId(Int64.ofInt(0)), "fileID 0 is not an object id");
	}

	// --------------------------------------------------------------- hand built

	static function handBuiltIndex():Void
	{
		Assert.test("GuidIndex.handBuilt");

		var index = new AssetGuidIndex();
		index.addEntry("6EB88238706C38746BB3E2A2BE435BE3", "Assets/Art/Materials/plane.mat", AssetKind.NativeAsset, Origin.Project,
			Int64.ofInt(2100000), "NativeFormatImporter");
		index.addEntry("b5b59a04266677f4db30660c10721917", "Assets/Art/Textures/2-1.png", AssetKind.Texture, Origin.Project,
			Int64.ofInt(2800000), "TextureImporter");

		Assert.equals(index.size(), 2, "two assets are indexed");
		// GUIDs are compared case insensitively, because a serialised reference may
		// carry either case.
		Assert.equals(index.pathOf("6eb88238706c38746bb3e2a2be435be3"), "Assets/Art/Materials/plane.mat", "lookup by guid");
		Assert.equals(index.guidOf("Assets/Art/Textures/2-1.png"), "b5b59a04266677f4db30660c10721917", "reverse lookup by path");
		Assert.equals(index.countOfKind(AssetKind.Texture), 1, "counting by kind");

		var entry = index.locate("6eb88238706c38746bb3e2a2be435be3");
		Assert.equals(entry.kind, AssetKind.NativeAsset, "the kind is kept");
		Assert.equals(Int64.toStr(entry.mainId), "2100000", "the main object id is kept");
		Assert.equals(entry.extension(), "mat", "the extension is derived");
		Assert.equals(entry.fileName(), "plane.mat", "the file name is derived");

		// Removing by guid is what the cache uses to drop an asset.
		Assert.isTrue(index.remove("6eb88238706c38746bb3e2a2be435be3"), "remove reports success");
		Assert.equals(index.size(), 1, "the asset is gone");
		Assert.isFalse(index.remove("6eb88238706c38746bb3e2a2be435be3"), "removing twice reports failure");
	}

	// --------------------------------------------------------------- resolution

	static function resolution():Void
	{
		Assert.test("GuidIndex.resolution");

		var index = new AssetGuidIndex();
		index.addEntry("506c261dd94da1d4c93293b19207e8b0", "Assets/mat.mat", AssetKind.NativeAsset, Origin.Project, Int64.ofInt(2100000));

		var local = index.resolve(UnityReference.local(Int64.ofInt(42)));
		Assert.isTrue(local.isLocal(), "a reference without a guid is local");
		Assert.isFalse(local.hasFile(), "a local reference has no file of its own");

		var builtin = index.resolve(UnityReference.asset("0000000000000000e000000000000000", Int64.ofInt(10210), 0));
		Assert.isTrue(builtin.isBuiltin(), "a built-in guid resolves as built-in");
		Assert.isFalse(builtin.hasFile(), "a built-in has no file");
		Assert.isTrue(builtin.isMainObject, "a built-in id is the object itself");

		var missing = index.resolve(UnityReference.asset("ffffffffffffffffffffffffffffffff", Int64.ofInt(1), 2));
		Assert.isTrue(missing.isMissing(), "an unknown guid is reported missing, not null");

		var hit = index.resolve(UnityReference.asset("506c261dd94da1d4c93293b19207e8b0", Int64.ofInt(2100000), 2));
		Assert.equals(hit.path(), "Assets/mat.mat", "an external reference resolves to a path");
		Assert.isTrue(hit.isMainObject, "the main object id is recognised");
		Assert.equals(hit.kind(), AssetKind.NativeAsset, "the kind comes through");

		var other = index.resolve(UnityReference.asset("506c261dd94da1d4c93293b19207e8b0", Int64.ofInt(99), 2));
		Assert.isFalse(other.isMainObject, "a different sub object id is not the main object");
	}

	// -------------------------------------------------------------------- cache

	static function cache(first:Bool):Void
	{
		Assert.test("GuidIndex.cache");
		cleanProject();

		writeAsset(root + "/Assets/Art", "aaa.mat", "11111111111111111111111111111111", "NativeFormatImporter", "2100000");
		writeAsset(root + "/Assets/Scripts", "bbb.cs", "22222222222222222222222222222222", "MonoImporter", null);

		var firstOpen = CachedGuidIndex.open(root, cacheFile);
		var r1 = firstOpen.refresh();
		Assert.isFalse(firstOpen.isLoaded(), "nothing was cached yet");
		Assert.isTrue(r1.rebuilt, "the first refresh rebuilds");
		Assert.equals(r1.entryCount, 2, "both assets are indexed");
		Assert.equals(firstOpen.index.pathOf("11111111111111111111111111111111"), "Assets/Art/aaa.mat", "the path is right");

		// A cache with nothing changed is used as is.
		var second = CachedGuidIndex.open(root, cacheFile);
		Assert.isTrue(second.isLoaded(), "the cache loads");
		Assert.equals(second.size(), 2, "the cache restores every asset");
		var r2 = second.refresh();
		Assert.isTrue(r2.valid, "an unchanged project is valid");
		Assert.isFalse(r2.rebuilt, "and is not rebuilt");
		Assert.equals(r2.rescanedDirs.length, 0, "and no directory is re-read");

		// Editing a .meta file in place changes no directory listing and no asset
		// identity, so the cache must stay valid.
		var metaPath = root + "/Assets/Art/aaa.mat.meta";
		sys.io.File.saveContent(metaPath, sys.io.File.getContent(metaPath) + "userData: edited\n");
		var edited = CachedGuidIndex.open(root, cacheFile);
		var r3 = edited.refresh();
		Assert.isTrue(r3.valid, "an in-place edit does not invalidate the cache");

		// Adding a file has to be noticed.
		sleep();
		writeAsset(root + "/Assets/Art", "ccc.png", "33333333333333333333333333333333", "TextureImporter", null);
		var added = CachedGuidIndex.open(root, cacheFile);
		var r4 = added.refresh();
		Assert.isFalse(r4.valid, "an added file invalidates the cache");
		Assert.equals(added.index.size(), 3, "the new asset is indexed");
		Assert.equals(added.index.pathOf("33333333333333333333333333333333"), "Assets/Art/ccc.png", "with the right path");

		// Deleting a file has to drop its entry.
		sleep();
		sys.FileSystem.deleteFile(root + "/Assets/Art/ccc.png.meta");
		sys.FileSystem.deleteFile(root + "/Assets/Art/ccc.png");
		var deleted = CachedGuidIndex.open(root, cacheFile);
		var r5 = deleted.refresh();
		Assert.isFalse(r5.valid, "a deleted file invalidates the cache");
		Assert.equals(deleted.index.locate("33333333333333333333333333333333"), null, "the deleted asset is gone");

		// A new directory has to be discovered, and must not disturb the assets that
		// were already there. This is the case that a naive "rescan the parent"
		// implementation gets wrong, because a parent owns no assets of its own.
		sleep();
		writeAsset(root + "/Assets/NewFolder/Deep", "ddd.asset", "44444444444444444444444444444444", "NativeFormatImporter", "11400000");
		var newDir = CachedGuidIndex.open(root, cacheFile);
		var r6 = newDir.refresh();
		Assert.equals(newDir.index.pathOf("44444444444444444444444444444444"), "Assets/NewFolder/Deep/ddd.asset",
			"an asset in a new directory is indexed");
		Assert.equals(newDir.index.size(), 3, "the earlier assets survive adding a directory");
		Assert.notNull(newDir.index.locate("11111111111111111111111111111111"), "the material survived");

		// Deleting that directory has to drop its assets and nothing else.
		sleep();
		deleteTree(root + "/Assets/NewFolder");
		var removed = CachedGuidIndex.open(root, cacheFile);
		var r7 = removed.refresh();
		Assert.equals(removed.index.locate("44444444444444444444444444444444"), null, "a deleted directory's assets are dropped");
		Assert.equals(removed.index.size(), 2, "the unrelated assets remain");
		Assert.notNull(removed.index.locate("22222222222222222222222222222222"), "the script survived");

		// A cache from another project must not be used.
		var foreign = CachedGuidIndex.open("build/guid-other-project", cacheFile);
		Assert.isFalse(foreign.isLoaded(), "a cache for a different project is rejected");

		// And a forced refresh rebuilds.
		var forced = CachedGuidIndex.open(root, cacheFile);
		var r8 = forced.refresh(true);
		Assert.isTrue(r8.rebuilt, "forcing rebuilds");
		Assert.equals(r8.entryCount, 2, "the rebuilt index is correct");

		cleanProject();
	}

	// ------------------------------------------------------------------ helpers

	/** Waits past the one second directory timestamp resolution. **/
	static function sleep():Void
	{
		Sys.sleep(1.1);
	}

	/** Writes an asset and its `.meta` file. **/
	static function writeAsset(directory:String, name:String, guid:String, importer:String, mainId:String):Void
	{
		if (!sys.FileSystem.exists(directory)) sys.FileSystem.createDirectory(directory);
		sys.io.File.saveContent(directory + "/" + name, "content of " + name + "\n");
		var meta = "fileFormatVersion: 2\nguid: " + guid + "\n" + importer + ":\n  externalObjects: {}\n";
		if (mainId != null) meta += "  mainObjectFileID: " + mainId + "\n";
		sys.io.File.saveContent(directory + "/" + name + ".meta", meta);
	}

	static function deleteTree(path:String):Void
	{
		if (!sys.FileSystem.exists(path)) return;
		if (sys.FileSystem.isDirectory(path))
		{
			for (name in sys.FileSystem.readDirectory(path)) deleteTree(path + "/" + name);
			sys.FileSystem.deleteDirectory(path);
		}
		else
		{
			sys.FileSystem.deleteFile(path);
		}
	}

	/** Removes the scratch project and cache so each run starts clean. **/
	static function cleanProject():Void
	{
		deleteTree(root);
		if (sys.FileSystem.exists(cacheFile)) sys.FileSystem.deleteFile(cacheFile);
	}
}
