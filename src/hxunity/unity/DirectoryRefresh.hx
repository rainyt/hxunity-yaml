package hxunity.unity;

/**
	What [CachedGuidIndex.refreshDirectory] did.

	`added` and `removed` are GUID lists rather than counts because that is what
	an exporter needs: after writing a batch of assets it has to know which GUIDs
	the index now knows about, and after deleting one it has to know which
	references just went dangling.
**/
@:structInit
typedef DirectoryRefresh = {
	/** Directory that was re-read, relative to the project root. **/
	var directory:String;

	/** GUIDs indexed from it that were not indexed before. **/
	var added:Array<String>;

	/** GUIDs that are no longer there. **/
	var removed:Array<String>;

	/** True when the directory did not exist and could not be read. **/
	var missing:Bool;

	/** Assets in the whole index after the refresh. **/
	var entryCount:Int;

	/** Wall clock cost of the refresh, in milliseconds. **/
	var elapsedMs:Int;
}
