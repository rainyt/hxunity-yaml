package hxunity.unity;

/**
	Where an asset lives, which decides whether a `guid` can be resolved by
	walking the project at all.
**/
enum abstract Origin(String)
{
	/** Inside `Assets/`. **/
	var Project = "project";

	/** Inside `Packages/`, or a package cached under `Library/PackageCache/`. **/
	var Package = "package";

	/**
		Built into Unity itself rather than stored in the project.

		These use a fixed GUID with `type: 0` (see [BuiltinResources]) and can never
		be found by scanning `.meta` files, because no such file exists.
	**/
	var Builtin = "builtin";

	/** A reference that stays inside the file it was written in. **/
	var Local = "local";

	/** No asset is known under this GUID. **/
	var Missing = "missing";

	/** True when the asset is a file on disk that a scan can find. **/
	public function isOnDisk():Bool
	{
		return this == "project" || this == "package";
	}
}
