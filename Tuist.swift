import ProjectDescription

// CI sets TUIST_CI_SOURCE_PACKAGES_DIR to the cached package clone directory
// that xcodebuild also receives as -clonedSourcePackagesDirPath, so
// `tuist generate` and the test run resolve the package graph once instead of
// twice. Unset (local development, releases), Tuist resolves into Xcode's
// default location exactly as before.
let ciSourcePackagesDir = Environment.ciSourcePackagesDir.getString(default: "")

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            additionalPackageResolutionArguments: ciSourcePackagesDir.isEmpty
                ? []
                : ["-clonedSourcePackagesDirPath", ciSourcePackagesDir]
        )
    )
)
