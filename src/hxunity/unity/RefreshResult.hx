package hxunity.unity;

/**
	What [CachedGuidIndex.refresh] had to do.

	Reported so a caller can tell the cheap path from the expensive one: a run that
	took six milliseconds because nothing changed is a very different situation
	from one that rebuilt a 22,000 asset index, and only [valid] and [rebuilt]
	distinguish them.
**/
@:structInit
typedef RefreshResult = {
	/** True when the cache was used as is, with no directory re-read. **/
	var valid:Bool;

	/** True when the whole index was rebuilt from scratch. **/
	var rebuilt:Bool;

	/** Directories that were re-read, empty when [valid]. **/
	var rescanedDirs:Array<String>;

	/** Directories the validation considered. **/
	var directoryCount:Int;

	/** Assets in the index after the refresh. **/
	var entryCount:Int;

	/** Wall clock cost of the refresh, in milliseconds. **/
	var elapsedMs:Int;
}
