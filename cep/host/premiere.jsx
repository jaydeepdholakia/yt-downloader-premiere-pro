/**
 * YT Downloader - Premiere Pro ExtendScript
 * Handles importing downloaded files into the active Premiere Pro project.
 *
 * NOTE: ExtendScript uses ECMAScript 3 — no let/const, no arrow functions,
 * no template literals, no default parameters.
 */

/**
 * Import a file into the Premiere Pro project.
 * @param {string} filePath - Absolute path to the file on disk.
 * @param {string} binName  - Optional bin name. If provided and doesn't exist, it's created.
 * @returns {string} "OK" on success, "Error: ..." on failure.
 */
function importFileToProject(filePath, binName) {
    try {
        if (!app.project) {
            return "Error: No project is open.";
        }

        var fileArray = [filePath];
        var suppressUI = true;
        var targetBin = null;

        if (binName && binName.length > 0) {
            targetBin = findOrCreateBin(binName);
        }

        if (targetBin) {
            app.project.importFiles(fileArray, suppressUI, targetBin, false);
        } else {
            app.project.importFiles(fileArray);
        }

        return "OK";
    } catch (e) {
        return "Error: " + e.toString();
    }
}

/**
 * Find an existing top-level bin by name or create a new one.
 * @param {string} binName - Name of the bin to find or create.
 * @returns {ProjectItem|null} The bin ProjectItem, or null on failure.
 */
function findOrCreateBin(binName) {
    var rootItem = app.project.rootItem;

    // Search existing top-level bins
    for (var i = 0; i < rootItem.children.numItems; i++) {
        var child = rootItem.children[i];
        if (child.type === ProjectItemType.BIN && child.name === binName) {
            return child;
        }
    }

    // Bin doesn't exist — create it
    rootItem.createBin(binName);

    // Retrieve the newly created bin
    for (var i = 0; i < rootItem.children.numItems; i++) {
        var child = rootItem.children[i];
        if (child.type === ProjectItemType.BIN && child.name === binName) {
            return child;
        }
    }

    return null;
}
