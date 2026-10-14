package hxunity.unity;

/**
	Options for [AssetGuidIndex.scan].
**/
typedef ScanOptions = {
	/** 从传入的目录本身扫描，不要求它是 Unity 工程根目录。 */
	@:optional var scanFromRoot:Bool;

	/**
		Index `Packages/` as well as `Assets/`.

		Defaults to true: project files reference assets that live in packages, so
		leaving them out would make those references unresolvable.
	**/
	@:optional var includePackages:Bool;

	/** Extra directory names to skip, matched case insensitively. **/
	@:optional var skip:Array<String>;

	/** Called with each directory as it is entered, for progress reporting. **/
	@:optional var onDirectory:String->Void;
}
