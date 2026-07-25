fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to TestFlight (UAT)

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and submit to the App Store for review

### ios notes

```sh
[bundle exec] fastlane ios notes
```

Set the What's New text from release_notes.txt without building or submitting

### ios builds

```sh
[bundle exec] fastlane ios builds
```

List the most recent uploaded builds and their processing state

### ios status

```sh
[bundle exec] fastlane ios status
```

Show the current review submission state and which build is attached

### ios resubmit

```sh
[bundle exec] fastlane ios resubmit
```

Cancel a stuck/rejected review submission and resubmit the already-uploaded build

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
