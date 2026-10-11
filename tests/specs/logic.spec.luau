local Loader = require("../harness/Loader")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local SeededRandom = Loader.load("src/shared/Util/SeededRandom")
	local RateLimiter = Loader.load("src/shared/Util/RateLimiter")
	local SignalModel = Loader.load("src/shared/Logic/SignalModel")
	local SignalConfig = Loader.load("src/shared/Config/SignalConfig")
	local AnchorMachine = Loader.load("src/shared/Logic/AnchorMachine")
	local AnchorConfig = Loader.load("src/shared/Config/AnchorConfig")
	local PhaseClock = Loader.load("src/shared/Logic/PhaseClock")
	local SessionMachine = Loader.load("src/shared/Logic/SessionMachine")
	local ObjectiveTracker = Loader.load("src/shared/Logic/ObjectiveTracker")
	local EventSelector = Loader.load("src/shared/Logic/EventSelector")
	local EndingEvaluator = Loader.load("src/shared/Logic/EndingEvaluator")
	local GameConfig = Loader.load("src/shared/Config/GameConfig")

	describe("SeededRandom", function()
		it("is deterministic for a seed", function()
			local a, b = SeededRandom.new(1998), SeededRandom.new(1998)
			for _ = 1, 50 do
				expect(a:NextNumber()).toBe(b:NextNumber())
			end
		end)
		it("stays in range and covers the range", function()
			local rng = SeededRandom.new(42)
			local seen = {}
			for _ = 1, 2000 do
				local v = rng:NextInteger(1, 6)
				expect(v >= 1 and v <= 6).toBeTruthy()
				seen[v] = true
			end
			for v = 1, 6 do
				expect(seen[v]).toBeTruthy()
			end
		end)
		it("forks independent streams", function()
			local base = SeededRandom.new(7)
			local x, y = base:Fork("events"), base:Fork("anchor")
			expect(x:NextNumber() ~= y:NextNumber()).toBeTruthy()
		end)
		it("shuffles without losing items", function()
			local list = SeededRandom.new(3):Shuffle({ 1, 2, 3, 4, 5 })
			table.sort(list)
			expect(table.concat(list, ",")).toBe("1,2,3,4,5")
		end)
	end)

	describe("RateLimiter", function()
		it("allows a burst then throttles and refills", function()
			local limiter = RateLimiter.new(3, 1)
			expect(limiter:Allow("p", 0)).toBeTruthy()
			expect(limiter:Allow("p", 0)).toBeTruthy()
			expect(limiter:Allow("p", 0)).toBeTruthy()
			expect(limiter:Allow("p", 0)).toBeFalsy()
			expect(limiter:Allow("p", 1.01)).toBeTruthy()
		end)
	end)

	describe("SignalModel", function()
		local function settle(state, seconds)
			local events = {}
			for _ = 1, seconds * 10 do
				for _, e in SignalModel.step(state, 0.1) do
					table.insert(events, e)
				end
			end
			return events
		end

		it("starts degraded and reaches full quality once maintained", function()
			local s = SignalModel.new(69.35)
			settle(s, 5)
			expect(s.quality).toBeLessThan(30)
			s.panelA, s.panelB, s.frequency = true, true, SignalConfig.CarrierFrequency
			settle(s, 10)
			expect(s.quality).toBeGreaterThan(95)
		end)

		it("penalises an empty VTR on air", function()
			local s = SignalModel.new(69.35)
			s.consolePowered, s.panelA, s.panelB, s.frequency = true, true, true, 55.25
			expect(SignalModel.setOnAir(s, "VTR")).toBeTruthy()
			expect(SignalModel.targetQuality(s)).toBeNear(100 - SignalConfig.Penalty.VTREmpty)
		end)

		it("rejects program changes while the console is off", function()
			local s = SignalModel.new(69.35)
			local ok, reason = SignalModel.setOnAir(s, "Studio")
			expect(ok).toBeFalsy()
			expect(reason).toBe("ConsoleOff")
		end)

		it("detuning to listen costs broadcast quality", function()
			local s = SignalModel.new(69.35)
			s.panelA, s.panelB, s.frequency = true, true, 55.25
			local tuned = SignalModel.targetQuality(s)
			s.frequency = 98.7
			expect(SignalModel.targetQuality(s)).toBeLessThan(tuned * 0.5)
		end)

		it("fires CarrierDropped once after the dead-air grace only when armed", function()
			local s = SignalModel.new(69.35)
			local events = settle(s, SignalConfig.DeadAirGrace + 5)
			expect(table.find(events, "CarrierDropped")).toBe(nil)
			s.deadAirArmed = true
			events = settle(s, SignalConfig.DeadAirGrace + 5)
			local count = 0
			for _, e in events do
				if e == "CarrierDropped" then
					count += 1
				end
			end
			expect(count).toBe(1)
		end)

		it("slate runs, returns to the previous source and then cools down", function()
			local s = SignalModel.new(69.35)
			s.consolePowered = true
			SignalModel.setOnAir(s, "VTR")
			expect(SignalModel.setOnAir(s, "Slate")).toBeTruthy()
			local events = settle(s, SignalConfig.Slate.Duration + 1)
			expect(table.find(events, "SlateEnded") ~= nil).toBeTruthy()
			expect(s.onAir).toBe("VTR")
			local ok, reason = SignalModel.setOnAir(s, "Slate")
			expect(ok).toBeFalsy()
			expect(reason).toBe("SlateCooldown")
		end)

		it("channel 0 needs the zero channel open and the lost frequency counts as tuned", function()
			local s = SignalModel.new(69.35)
			s.consolePowered = true
			expect(SignalModel.setOnAir(s, "Channel0")).toBeFalsy()
			s.zeroChannelOpen = true
			s.frequency = 69.35
			expect(SignalModel.tuningFactor(s)).toBe(1)
			expect(SignalModel.setOnAir(s, "Channel0")).toBeTruthy()
		end)
	end)

	describe("PhaseClock", function()
		it("stalls just before the cap until objectives are complete", function()
			local timing = GameConfig.Phases.Maintenance
			local clock, reached = PhaseClock.advance(timing.cap - 0.01, timing, 10, false)
			expect(reached).toBeFalsy()
			expect(clock).toBeLessThan(timing.cap)
			clock, reached = PhaseClock.advance(clock, timing, 10, true)
			expect(reached).toBeTruthy()
			expect(clock).toBe(timing.cap)
		end)
		it("phase clock ranges chain without gaps", function()
			local order = GameConfig.PhaseOrder
			for i = 1, #order - 1 do
				local a, b = GameConfig.Phases[order[i]], GameConfig.Phases[order[i + 1]]
				expect(b.startClock >= a.cap).toBeTruthy()
				expect(b.startClock - a.cap <= 1).toBeTruthy()
			end
		end)
	end)

	describe("SessionMachine", function()
		it("only allows the declared flow", function()
			expect(SessionMachine.canTransition("Lobby", "Intro")).toBeTruthy()
			expect(SessionMachine.canTransition("Lobby", "Running")).toBeFalsy()
			expect(SessionMachine.canTransition("Results", "Lobby")).toBeFalsy()
			expect(SessionMachine.canTransition("Resetting", "Lobby")).toBeTruthy()
		end)
	end)

	describe("AnchorMachine", function()
		local function ctx(overrides)
			local c = {
				phase = "Escalation",
				pressure = 0.5,
				slateActive = false,
				deadAir = false,
				hasTarget = true,
				targetLostFor = 0,
				caught = false,
				aggression = 1,
			}
			for k, v in overrides or {} do
				c[k] = v
			end
			return c
		end

		it("stays dormant before the anomaly", function()
			local m = AnchorMachine.new(SeededRandom.new(1))
			AnchorMachine.step(m, 1, ctx({ phase = "Maintenance" }))
			expect(m.state).toBe("Dormant")
		end)

		it("walks Dormant -> Broadcast -> Observing -> Displacement", function()
			local m = AnchorMachine.new(SeededRandom.new(1))
			AnchorMachine.step(m, 0.1, ctx({ phase = "Anomaly" }))
			expect(m.state).toBe("Broadcast")
			for _ = 1, AnchorConfig.BroadcastMinDuration * 10 + 5 do
				AnchorMachine.step(m, 0.1, ctx())
			end
			expect(m.state).toBe("Observing")
			for _ = 1, 600 do
				AnchorMachine.step(m, 0.1, ctx())
				if m.state ~= "Observing" then
					break
				end
			end
			expect(m.state).toBe("Displacement")
		end)

		it("pre-echo always precedes the physical appearance", function()
			local m = AnchorMachine.new(SeededRandom.new(9))
			m.state = "Observing"
			m.stateDuration = 0
			local sawPreEcho, appearedAfterEcho = false, false
			for _ = 1, 2000 do
				for _, e in AnchorMachine.step(m, 0.1, ctx({ pressure = 0.1 })) do
					if e.kind == "PreEcho" then
						sawPreEcho = true
					elseif e.kind == "Appear" then
						appearedAfterEcho = sawPreEcho
					end
				end
				if appearedAfterEcho then
					break
				end
			end
			expect(appearedAfterEcho).toBeTruthy()
		end)

		it("never catches during the hunt telegraph", function()
			local m = AnchorMachine.new(SeededRandom.new(2))
			m.state = "Manifestation"
			AnchorMachine.force(m, "Hunt", ctx(), "test")
			local t = 0
			while t < AnchorConfig.HuntTelegraph - 0.2 do
				AnchorMachine.step(m, 0.1, ctx({ caught = true }))
				expect(AnchorMachine.canCatch(m)).toBeFalsy()
				expect(m.state).toBe("Hunt")
				t += 0.1
			end
		end)

		it("hunts end: caught, lost target, slate or timeout", function()
			for _, case in { { caught = true }, { targetLostFor = 99 }, { slateActive = true }, {} } do
				local m = AnchorMachine.new(SeededRandom.new(3))
				m.state = "Manifestation"
				AnchorMachine.force(m, "Hunt", ctx(), "test")
				for _ = 1, 600 do
					AnchorMachine.step(m, 0.1, ctx(case))
					if m.state ~= "Hunt" then
						break
					end
				end
				expect(m.state).toBe("Withdrawal")
				expect(m.huntCooldown).toBeGreaterThan(0)
			end
		end)

		it("does not hunt below the pressure threshold outside Crisis", function()
			local m = AnchorMachine.new(SeededRandom.new(4))
			m.state = "Displacement"
			AnchorMachine.force(m, "Manifestation", ctx(), "test")
			for _ = 1, 100 do
				AnchorMachine.step(m, 0.1, ctx({ pressure = 0.4 }))
			end
			expect(m.state ~= "Hunt").toBeTruthy()
		end)

		it("rejects illegal forced transitions", function()
			local m = AnchorMachine.new(SeededRandom.new(5))
			local events, err = AnchorMachine.force(m, "Hunt", ctx(), "test")
			expect(events).toBe(nil)
			expect(err ~= nil).toBeTruthy()
		end)

		it("every transition taken over a long simulated night is legal", function()
			local m = AnchorMachine.new(SeededRandom.new(1234))
			local phases = { "Anomaly", "Escalation", "Crisis" }
			for _, phase in phases do
				for i = 1, 3000 do
					AnchorMachine.step(m, 0.1, ctx({
						phase = phase,
						pressure = if phase == "Crisis" then 0.8 else 0.45,
						caught = i % 400 == 0,
						slateActive = i % 777 < 20,
					}))
				end
			end
			for _, edge in m.history do
				expect(AnchorMachine.canTransition(edge.from, edge.to)).toBeTruthy()
			end
		end)

		it("pressure grows with phase and channel 0", function()
			local base = { phase = "Escalation", phaseProgress = 0.5, channel0OnAir = false, deadAir = false, carrierDrops = 0, isolation = 0, aggression = 1 }
			local p1 = AnchorMachine.pressure(base)
			base.channel0OnAir = true
			local p2 = AnchorMachine.pressure(base)
			base.phase = "Crisis"
			local p3 = AnchorMachine.pressure(base)
			expect(p2).toBeGreaterThan(p1)
			expect(p3).toBeGreaterThan(p2)
			base.phase = "Maintenance"
			base.channel0OnAir = false
			expect(AnchorMachine.pressure(base)).toBe(0)
		end)
	end)

	describe("ObjectiveTracker", function()
		it("scales camera checks with crew size and latches completion", function()
			local tracker = ObjectiveTracker.new(1)
			local facts, counters = {}, { camerasChecked = 4 }
			ObjectiveTracker.evaluate(tracker, facts, counters)
			expect(tracker.done.check_cameras).toBeTruthy()

			local four = ObjectiveTracker.new(4)
			ObjectiveTracker.evaluate(four, facts, counters)
			expect(four.done.check_cameras).toBe(nil)
			counters.camerasChecked = 6
			ObjectiveTracker.evaluate(four, facts, counters)
			expect(four.done.check_cameras).toBeTruthy()
		end)

		it("phase completes only when blocking objectives are done", function()
			local tracker = ObjectiveTracker.new(2)
			local facts = { signedIn = true, reachedMCR = true }
			ObjectiveTracker.evaluate(tracker, facts, {})
			expect(ObjectiveTracker.phaseComplete(tracker, "Arrival")).toBeFalsy()
			facts.consolePowered = true
			ObjectiveTracker.evaluate(tracker, facts, {})
			-- watch_orientation is optional
			expect(ObjectiveTracker.phaseComplete(tracker, "Arrival")).toBeTruthy()
			facts.consolePowered = false
			ObjectiveTracker.evaluate(tracker, facts, {})
			expect(ObjectiveTracker.phaseComplete(tracker, "Arrival")).toBeTruthy()
		end)

		it("a crew shrinking after a disconnect never raises a goal", function()
			local tracker = ObjectiveTracker.new(4)
			ObjectiveTracker.setPlayerCount(tracker, 1)
			ObjectiveTracker.evaluate(tracker, {}, { camerasChecked = 4 })
			expect(tracker.done.check_cameras).toBeTruthy()
		end)
	end)

	describe("EventSelector", function()
		local function context(now, phase, facts)
			return { now = now, phase = phase, facts = facts or {}, anchorState = "Observing", hasIsolated = false, blocked = false }
		end

		it("respects phase windows", function()
			local sel = EventSelector.new()
			local def = EventSelector.find(sel, "impossible_broadcast")
			expect(EventSelector.eligible(sel, def, context(100, "Maintenance"))).toBeFalsy()
			sel.budget = 1
			expect(EventSelector.eligible(sel, def, context(100, "Escalation"))).toBeTruthy()
		end)

		it("enforces cooldowns, repeats and the calm after critical events", function()
			local sel = EventSelector.new()
			sel.budget = 1.2
			local crit = EventSelector.find(sel, "blackout_wing")
			local facts = { panelAUp = true, panelBUp = true }
			expect(EventSelector.eligible(sel, crit, context(100, "Escalation", facts))).toBeTruthy()
			EventSelector.record(sel, crit, 100)
			local ok, why = EventSelector.eligible(sel, crit, context(110, "Escalation", facts))
			expect(ok).toBeFalsy()
			local inter = EventSelector.find(sel, "impossible_broadcast")
			sel.budget = 1.2
			ok, why = EventSelector.eligible(sel, inter, context(110, "Escalation", facts))
			expect(ok).toBeFalsy()
			expect(why == "calm" or why == "tierGap").toBeTruthy()
		end)

		it("never blocks while a cinematic runs", function()
			local sel = EventSelector.new()
			local ctx = context(500, "Escalation")
			ctx.blocked = true
			expect(EventSelector.choose(sel, ctx, SeededRandom.new(1))).toBe(nil)
		end)

		it("does not repeat the same event back to back over a long night", function()
			local sel = EventSelector.new()
			local rng = SeededRandom.new(77)
			local facts = { panelAUp = true, panelBUp = true, carrierHeld = true, fillerInMCR = true }
			local last
			for step = 1, 600 do
				local now = step * 3
				EventSelector.refill(sel, "Crisis", 3)
				local ctx = context(now, "Crisis", facts)
				local def = EventSelector.choose(sel, ctx, rng)
				if def then
					expect(def.id ~= last).toBeTruthy()
					last = def.id
					EventSelector.record(sel, def, now)
				end
			end
		end)

		it("respects requirements", function()
			local sel = EventSelector.new()
			sel.budget = 1.2
			local tapeVoice = EventSelector.find(sel, "tape_extra_voice")
			expect(EventSelector.eligible(sel, tapeVoice, context(100, "Escalation", {}))).toBeFalsy()
			expect(EventSelector.eligible(sel, tapeVoice, context(100, "Escalation", { tapePlaying = true }))).toBeTruthy()
		end)
	end)

	describe("EndingEvaluator", function()
		it("lists what is missing", function()
			local met, missing = EndingEvaluator.check("CutSignal", { phaseCrisis = true })
			expect(met).toBeFalsy()
			expect(missing[1]).toBe("req.hasKillKey")
			met = EndingEvaluator.check("CutSignal", { phaseCrisis = true, hasKillKey = true })
			expect(met).toBeTruthy()
		end)
		it("full broadcast needs every clue step", function()
			local facts = { phaseCrisis = true, allClueTapesViewed = true, lostFrequencyLocked = true, masterInMCR = true }
			expect(EndingEvaluator.check("FullBroadcast", facts)).toBeFalsy()
			facts.channel0OnAir = true
			expect(EndingEvaluator.check("FullBroadcast", facts)).toBeTruthy()
		end)
		it("reports every ending", function()
			expect(#EndingEvaluator.report({})).toBe(5)
		end)
	end)
end
