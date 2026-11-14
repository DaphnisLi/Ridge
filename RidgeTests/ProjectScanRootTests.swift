import XCTest
@testable import Ridge

final class ProjectScanRootTests: XCTestCase {
    func test_scanRoot_walksUpToNearestProjectAndUsesParentAsRoot() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("ridge-scan-root-\(UUID().uuidString)", isDirectory: true)
        let workspace = base.appendingPathComponent("workspace", isDirectory: true)
        let project = workspace.appendingPathComponent("DemoApp", isDirectory: true)
        let nested = project.appendingPathComponent("src", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: project.appendingPathComponent("Package.swift"))

        // 用家目录前缀绕过 scanRoot 的 home 守卫：把临时树挂到临时 home 语义下不可行，
        // 因此这里只验证 identify 链条在真实路径上能命中；根路径规则用绝对路径手工对齐。
        let hit = ProjectCatalog.scanRoot(forWorkingDirectory: nested.path)
        // 临时目录不在 $HOME 下时应返回 nil。
        XCTAssertNil(hit)

        // 在 $HOME 下建一棵临时工程树再测完整契约。
        let homeBase = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".ridge-test-scan-\(UUID().uuidString)", isDirectory: true)
        let homeWorkspace = homeBase.appendingPathComponent("code", isDirectory: true)
        let homeProject = homeWorkspace.appendingPathComponent("App", isDirectory: true)
        let homeNested = homeProject.appendingPathComponent("Sources", isDirectory: true)
        defer { try? fm.removeItem(at: homeBase) }
        try fm.createDirectory(at: homeNested, withIntermediateDirectories: true)
        try Data().write(to: homeProject.appendingPathComponent("Package.swift"))

        let homeHit = ProjectCatalog.scanRoot(forWorkingDirectory: homeNested.path)
        XCTAssertEqual(homeHit?.projectPath, homeProject.path)
        let expectedRoot = homeWorkspace.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        XCTAssertEqual(homeHit?.root, expectedRoot)

        try? fm.removeItem(at: base)
    }

    func test_scanRoot_projectDirectlyUnderHomeUsesProjectAsRoot() throws {
        let fm = FileManager.default
        let homeProject = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".ridge-test-alone-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: homeProject) }
        try fm.createDirectory(at: homeProject, withIntermediateDirectories: true)
        try Data().write(to: homeProject.appendingPathComponent("package.json"))

        let hit = ProjectCatalog.scanRoot(forWorkingDirectory: homeProject.path)
        let expected = homeProject.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        XCTAssertEqual(hit?.projectPath, homeProject.path)
        XCTAssertEqual(hit?.root, expected)
    }
}
