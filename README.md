[![Automatic version updates](https://github.com/ZOSOpenTools/gitport/actions/workflows/bump.yml/badge.svg)](https://github.com/ZOSOpenTools/gitport/actions/workflows/bump.yml)

# Git

The Git version control system

# Installation and Usage

Use the zopen package manager ([QuickStart Guide](https://zopen.community/#/Guides/QuickStart)) to install:
```bash
zopen install git
```

# Building from Source

1. Clone the repository:
```bash
git clone https://github.com/zopencommunity/gitport.git
cd gitport
```
2. Build using zopen:
```bash
zopen build -vv
```

See the [zopen porting guide](https://zopen.community/#/Guides/Porting) for more details.

# Documentation
## Encoding considerations
Git on z/OS leverages Git's `.gitattributes` support to enable support for various encodings, documented [here](https://git-scm.com/docs/gitattributes). 
`.gitattributes` can be specified globally, or locally in repositories to determine the encoding of working tree files.

### Working-tree-encoding
The `working-tree-encoding` attribute can be used to determine the working tree encoding. For example,
to convert all files from Git's internal UTF-8 encoding to IBM-1047, you can specify the following working-tree-encoding in your .gitattributes file:
```
* text working-tree-encoding=IBM-1047
```
This will result in Git on z/OS tagging all files as IBM-1047 on checkout. 

If you want the working-tree-encoding to apply to the host platform only, then you can use:
`platform-working-tree-encoding` where platform is substituted with the system name.

On z/OS, platform is `zos`. Therefore, the .gitattributes would be:
```
* text zos-working-tree-encoding=IBM-1047
```

If no encoding is specified, the default UTF-8 encoding is used and all files are tagged as ISO8859-1. 

To find out all of the supported encodings by git, run `iconv -l`.

When adding files, you need to make sure that the z/OS file tag matches the working-tree-encoding. Otherwise, you may encounter an error.

**Important Note:** If you are relying on the zos-working-tree-encoding support and you are editing your git-managed files on a non-z/OS platform, make sure that the files are encoded in UTF-8 mode. This is because Git assumes such files are encoded in UTF-8 prior to conversion. See [the working-tree-encoding documentation](https://git-scm.com/docs/gitattributes#_working_tree_encoding) for more details.  If you insist on editing your files in a different encoding, make sure to add the `working-tree-encoding` to the .gitattributes to reflect the codepage:

```
*  zos-working-tree-encoding=ibm-1047 working-tree-encoding=iso8859-1
```
This indicates that the file will be encoded in IBM-1047 on z/OS, but on non-z/OS platforms, it will be encoded in iso8859-1. 

### Encodings and z/OS File Tags (CCSIDs)

**Note:** Git on z/OS now aligns the file tag (CCSID) with the git working-tree-encoding by default. Previously, there was a specific handling for UTF-8 encoded files. These files were tagged as ISO8859-1 (CCSID 819) due to z/OS Open Tools' behavior under _BPXK_AUTOCVT=ON, which doesn't auto-convert files tagged with the UTF-8 tag (CCSID 1208).
Consequently, the default tag for UTF-8 encoded files is now UTF-8 (or CCSID 1208).

To adjust the default tag for UTF-8, you can configure the git setting `core.utf8ccsid` to 819 using the following commands:

- `git config --global core.utf8ccsid 819` # Global setting, 819 represents the CCSID for the UTF8 file tag
- `git config core.utf8ccsid 819` # Local setting affecting the current repository

Alternatively, you can set the GIT_UTF8_CCSID environment variable:

- `export GIT_UTF8_CCSID=819` # Environment variable

The environment variable takes precedence over the git config setting.

#### Example
Assuming you want to clone UTF-8 encoded files with the tag UTF8 or ccsid 819 as opposed to the default ccsid (1208):

```
git config --global core.utf8ccsid 819 # Set the UTF-8 ccsid 819 globally
git clone https://github.com/git/git
cd git
ls -lT # you will notice that all files are now tagged as 819
```

### Binary files
To specify a binary encoding, you can use the binary attribute as follows:
```
*.png binary
```
This will tag all `*.png` files as binary.

### Untagged files
Git on z/OS does not currently support adding `untagged` files. Files need to be tagged before
they can be added.

### Multiple encodings
You can specify multiple working-tree-encoding attributes, where the later attributes overrides the initial attributes in case of an overlap.
```
* text working-tree-encoding=IBM-1047
*.png binary
```

### Migration considerations
If you are migrating from Rocket Software's Git, then the good news is that Git on z/OS should be compatible. 

If you encounter any issues, please open an issue under https://github.com/zopencommunity/gitport/issues.

# Git Performance considerations

This section provides various strategies to improve Git performance. It covers approaches that reduce the amount of data processed by Git, fine-tuning configuration parameters, and addresses specific considerations for encoding conversions in the working tree. Each section offers explanations and examples to help users optimize Git operations in large repositories, CI/CD environments, and systems with high I/O demands.

## 1. Data Reduction Strategies

Data reduction strategies are centered around minimizing the amount of data that Git must download, process, or store. By reducing the data footprint, you not only decrease network usage and disk I/O but also lower the CPU cycles required during operations.

### Shallow Clones

- **Purpose:**  
  Shallow clones limit the history depth that Git downloads. Instead of cloning the entire commit history of a repository, a shallow clone (`--depth=n`) retrieves only the latest commits (often just the most recent commit). This is particularly useful in **CI/CD pipelines** or automated builds where the full commit history is not needed.

- **Benefits:**  
  - **Reduced Data Transfer:** Only a subset of the commit history is downloaded, which saves bandwidth.  
  - **Faster Cloning:** Cloning operations become much quicker as less data is processed.  
  - **Lower CPU and Memory Usage:** With fewer commits to process, the resource consumption is significantly reduced.

- **Example Command:**
  ```bash
  git clone --depth=1 <repo-url> my-repo
  ```
  This command tells Git to perform a shallow clone with a depth of 1, meaning only the latest commit is cloned. This is particularly useful in in CI/CD build pipelines where logs are not accessed.

### Sparse Checkouts

- **Purpose:**  
  Sparse checkouts allow you to restrict the working directory to a specific subset of files or directories within the repository. This is highly beneficial for large repositories where only a few directories are required for a particular task. 

- **Benefits:**  
  - **Reduced Disk Usage:** Only the necessary files are checked out, saving disk space.
  - **Improved Performance:** Fewer files mean less overhead for file system operations, leading to faster checkout and status commands.

- **Example Workflow:**
  1. Clone the repository normally:
     ```bash
     git clone <repo-url> my-repo
     cd my-repo
     ```
  2. Initialize sparse checkout mode:
     ```bash
     git sparse-checkout init --cone
     ```
  3. Specify the directories to be checked out:
     ```bash
     git sparse-checkout set src include
     ```
  This setup ensures that only the directories `src` and `include` are present in the working directory, thereby reducing unnecessary data processing.

### Avoid Downloading Large Binaries

- **Purpose:**  
  In repositories containing large binary files or blobs that are not needed for every operation, you can instruct Git to filter these out during the cloning process. This helps in managing bandwidth and disk space effectively.

- **Benefits:**  
  - **Efficient Network Usage:** By not downloading large blobs, you reduce the time and data needed for cloning.
  - **Lower Processing Overhead:** Git spends less time handling unnecessary large objects.

- **Example Command:**
  ```bash
  git clone --filter=blob:none <repo-url>
  ```
  This command uses the `--filter=blob:none` option to prevent Git from downloading any large file blobs, making the clone operation leaner and faster.

---

## 2. Additional Strategies

Beyond data reduction, there are several additional strategies that can further enhance Git performance by optimizing internal Git processes and leveraging system resources more effectively.

### Advanced Parallelization

- **Purpose:**  
  Git can take advantage of multiple processors by parallelizing certain operations. This includes parallel checkouts and repack operations which are critical for large repositories.

- **Benefits:**  
  - **Reduced Checkout Time:** Parallel workers can process multiple files concurrently.
  - **Better Resource Utilization:** Full utilization of available CPU cores leads to overall performance improvement.

- **Example Configuration:**
  ```bash
  git config --global checkout.workers -1         # Use all available cores
  git config --global checkout.thresholdForParallelism 1000
  ```
  These settings instruct Git to use all available CPU cores for checkout operations and to trigger parallelism when the number of files exceeds a certain threshold.

### Compression and Garbage Collection

*   **Lower Compression Level (`core.compression`):**
    *   **Purpose:** Reduce CPU usage and improves fetch and clone performance by decreasing or disabling Git object compression.
    *   **Configuration:**
        ```bash
        git config --global core.compression <level>  # 0 for no compression, 1-9 for levels
        git config --global core.compression 0      # Disable compression
        ```
    *   **Consideration:** Trade-off between CPU and disk space. 

*   **Minimize Garbage Collection (`gc.auto`):**
    *   **Purpose:** Prevent performance dips by disabling automatic garbage collection.
    *   **Configuration:**
        ```bash
        git config --global gc.auto 0
        ```
    *   **Consideration:** May require manual `git gc` periodically.

### Performance-Enhancing Features

*   **`feature.manyFiles` Optimizations:**
    *   **Purpose:** Optimize for repositories with many files, improving commands like `git status` and `git checkout`.
    *   **Configuration:**
        ```bash
        git config --global feature.manyFiles true
        ```
    *   **Sub-options:** `index.skipHash`, `index.version`, `core.untrackedCache`.

*   **`core.ignoreStat`:**
    *   **Purpose:** Skip `lstat()` calls for change detection, beneficial if `lstat()` is slow on your system.
    *   **Configuration:**
        ```bash
        git config --global core.ignoreStat true
        ```
    *   **Consideration:** Default is `false`. Evaluate `lstat()` performance on z/OS.

### Profiling and Diagnostics

- **Purpose:**  
  Diagnostic environment variables such as `GIT_TRACE` and `GIT_TRACE_PERFORMANCE` help identify bottlenecks in Git operations. With the added logs, this can enable targeted performance tuning based on actual system behavior.

- **Benefits:**  
  - **Insight into Operations:** Detailed trace logs can reveal which steps are consuming the most time.

- **Usage:**  
  Set the environment variable before running Git commands:
  ```bash
  export GIT_TRACE=1
  export GIT_TRACE_PERFORMANCE=1
  ```
  This will output detailed trace information that can be analyzed to optimize performance further.


## 4. Working-Tree-Encoding: Performance Considerations

The `working-tree-encoding` or `zos-working-tree-encoding` attribute is designed to repository contents to a different encoding in the working directory. Although this is useful for projects that operate on a different encoding, it comes at a performance cost due to the on-the-fly conversions performed by the `iconv` library.

### How Working-Tree-Encoding Works

  When you define a `working-tree-encoding` in a `.gitattributes` file, Git automatically converts files from the repository's storage encoding to the specified encoding in the working tree during checkout. Conversely, when files are added or modified, Git converts them back to the repository's encoding.

- **Conversion Process:**  
  This conversion is handled by the `iconv` library, a library that transforms the file's encoding. While this ensures that files are accessible in the desired format, it introduces additional CPU overhead.

### Performance Impact

- **Using a Global Wildcard:**  
  Applying a global wildcard (i.e., `*`) for the `working-tree-encoding` attribute means that every file in the repository will undergo this conversion. For example:
  ```gitattributes
  * text zos-working-tree-encoding=ibm-1047
  ```
  **Impact:**  
  - **High CPU Usage:** Every file, regardless of type, is subject to encoding conversion.
  - **Slower Operations:** In repositories with a large number of files, this can significantly slow down checkouts, status checks, and other file operations.

### Use More Specific Patterns to Reduce Overhead

- **Targeting Specific File Types:**  
  Instead of applying the encoding conversion universally, restrict it to only those file types that require a specific encoding. For example, you may only need to convert source files, such as `.cob` or `.c` files:
  ```gitattributes
  *.cob text zos-working-tree-encoding=ibm-1047
  *.c text zos-working-tree-encoding=ibm-1047
  ```
  **Benefits:**  
  - **Reduced Conversion Load:** Only a subset of files is processed by `iconv`, alleviating the performance penalty.
  - **Focused Resource Usage:** System resources are concentrated on files that actually benefit from encoding conversion, improving overall efficiency.


## Troubleshooting
TBD

## Contributing
Contributions are welcome! Please follow the [zopen contribution guidelines](https://github.com/zopencommunity/meta/blob/main/CONTRIBUTING.md).
