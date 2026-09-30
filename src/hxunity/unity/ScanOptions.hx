package hxunity.unity;

/**
	Options for [AssetGuidIndex.scan].
**/
typedef ScanOptions = {
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
