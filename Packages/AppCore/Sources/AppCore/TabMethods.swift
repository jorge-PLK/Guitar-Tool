import Foundation

// Métodos `tab.*` (parte 8.7). Contrato: `Temp/win/step8-contract.md`, «8.7 Tablatura».

extension TabService {
    nonisolated func register(on router: Router) {
        router.register("tab.open") { [self] (p: TabOpenParams) -> TabState in try await open(projectId: p.projectId) }
        router.register("tab.state") { [self] (_: Empty) -> TabState in
            guard await isOpen else { throw RPCError(code: "not-open", message: "No hay ninguna tablatura abierta.") }
            return await state()
        }
        router.register("tab.close") { [self] (_: Empty) -> Empty in await close(); return Empty() }
        router.register("tab.setSource") { [self] (p: TabSourceParams) -> TabState in try await setSource(p.source) }
        registerSongsterr(on: router)
        router.register("tab.score") { [self] (p: TabTrackParams) -> TabScoreResult in try await scoreJSON(track: p.track) }
        router.register("tab.selectTrack") { [self] (p: TabTrackParams) -> TabState in
            guard let t = p.track else { throw RPCError(code: "bad-params", message: "Falta «track».") }
            return try await selectTrack(t)
        }
        router.register("tab.transcribe") { [self] (p: TabTrackParams) -> TabQueuedResult in try await transcribe(track: p.track) }
        router.register("tab.cancel") { [self] (_: Empty) -> CancelResult in CancelResult(cancelled: await cancel()) }
        router.register("tab.beatClick") { [self] (p: TabClickParams) -> TabState in
            try await beatClick(track: p.track, bar: p.bar, beat: p.beat, shift: p.shift ?? false)
            return await state()
        }
        router.register("tab.beatDrag") { [self] (p: TabClickParams) -> TabState in
            try await beatDrag(track: p.track, bar: p.bar, beat: p.beat)
            return await state()
        }
        router.register("tab.noteClick") { [self] (p: TabClickParams) -> TabState in
            try await noteClick(track: p.track, bar: p.bar, beat: p.beat, string: p.string ?? 0, shift: p.shift ?? false)
            return await state()
        }
        router.register("tab.select") { [self] (p: TabSelectParams) -> TabState in
            try await selectPoint(track: p.track, beat: p.beat, tick: p.tick, string: p.string)
        }
        router.register("tab.span") { [self] (p: TabSpanParams) -> TabState in try await spanAction(p.action, keepAnchor: p.keepAnchor ?? false) }
        router.register("tab.dismissNotices") { [self] (_: Empty) -> TabState in
            try await requireOpen()
            await dismissNotices()
            return await state()
        }
        router.register("tab.toggleMute") { [self] (p: TabTrackParams) -> TabState in
            guard let t = p.track else { throw RPCError(code: "bad-params", message: "Falta «track».") }
            try await toggleMute(trackID: t)
            return await state()
        }
        router.register("tab.toggleSolo") { [self] (p: TabTrackParams) -> TabState in
            guard let t = p.track else { throw RPCError(code: "bad-params", message: "Falta «track».") }
            try await toggleSolo(trackID: t)
            return await state()
        }
        router.register("tab.setListening") { [self] (p: TabListeningParams) -> TabState in
            guard let t = p.track else { throw RPCError(code: "bad-params", message: "Falta «track».") }
            try await requireOpen()
            await setListening(p.on, trackID: t)
            return await state()
        }
        router.register("tab.setAllListening") { [self] (p: TabListeningParams) -> TabState in
            try await setAllListening(p.on)
            return await state()
        }
        router.register("tab.edit") { [self] (p: TabEditParams) -> TabState in try await edit(p) }
        router.register("tab.exportName") { [self] (_: Empty) -> TabExportNameResult in try await exportName() }
        router.register("tab.export") { [self] (p: TabExportParams) -> TabExportResult in
            try await export(data: p.data, path: p.path)
        }
    }

    func requireOpen() throws {
        guard isOpen else { throw RPCError(code: "not-open", message: "No hay ninguna tablatura abierta.") }
    }
}

extension Bridge {
    /// Guarda la tablatura abierta; el anfitrión lo llama al cerrar la ventana, antes de `closeStudy`.
    public func closeTab() async { await tabService.close() }
}
