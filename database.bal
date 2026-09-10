public function searchAssets(string searchTerm) returns Asset[] {
    Asset[] results = [];

    foreach var [assetTag, asset] in assets.entries() {
        if asset.name.toLowerAscii().includes(searchTerm.toLowerAscii()) ||
           asset.description.toLowerAscii().includes(searchTerm.toLowerAscii()) ||
           asset.assetTag.toLowerAscii().includes(searchTerm.toLowerAscii()) {

            results.push(asset);
        }
    }

    return results;
}
