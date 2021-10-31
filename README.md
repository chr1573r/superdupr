# superdupr
Powerful duplicate file finder script
Spiritual sucessor to https://github.com/chr1573r/supdup

Syntax: ./superdupr <directory to analyze> <minimum file size in megabytes>

superdupr will recursively scan a directory and detect duplicate files.
A size filter can be specified if you want superdupr to only look at files above a given file size.

While scanning the directory, the current progress and statistics will be visualized in the terminal.
After the scan, a summary is printed out with filepaths to the identified duplicate files and how much disk space you can reclaim.

![Demo default gui](https://chr1573r.github.io/repo-assets/superdupr/demo_super.gif)

Alternate compact scan gui
![Demo default gui](https://chr1573r.github.io/repo-assets/superdupr/demo_compact.gif)

This is still a work in progress, expect bugs and bloat.

Features that might be added in the future:
 - Support that sizefilter can be specified in other units than just megabytes
 - Improved duplicate result view with pagination, sort by reclaimable space, save results to file etc
 - Duplicate cleanup wizard which will let you pick which files to keep and which duplicates to delete
 - Additional dedup analysis, such as detecting folders that share multiple duplicates each and suggesting to merge them together into a single location/collection
 