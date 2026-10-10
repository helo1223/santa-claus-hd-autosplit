state("SantaClausInTrouble")
{
    int gameState : 0x39BD00;
    int mode : 0x39BCE8, 0x08;
    uint level : 0x39BCE8, 0x14;
}

startup
{
    refreshRate = 120;
    vars.completed = new System.Collections.Generic.HashSet<uint>();
    vars.ready = false;
    vars.supported = false;
    vars.stopped = false;
    vars.finishPending = false;
    vars.saveError = "";
    vars.timerModel = new LiveSplit.Model.TimerModel { CurrentState = timer };
}

init
{
    vars.ready = false;
    // Relocation-free instruction bytes: reads +230, compares the requested state.
    // A focused compatibility check, not a guarantee for every modified executable.
    byte[] signature = { 0x8B, 0x83, 0x30, 0x02, 0x00, 0x00,
                         0x8B, 0x4D, 0x08, 0x3B, 0xC1 };
    byte[] actual = memory.ReadBytes(modules.First().BaseAddress + 0x2252D, signature.Length);
    vars.supported = actual != null && actual.SequenceEqual(signature);
    version = vars.supported ? "Steam HD / All levels" : "Unsupported executable";
    if (!vars.supported) print("Classic autosplitter: executable signature mismatch; disabled.");
}

update
{
    if (!vars.supported) return false;
    // Results removal pauses Game Time; ensure the displayed/default timing uses it.
    timer.CurrentTimingMethod = LiveSplit.Model.TimingMethod.GameTime;
    if (vars.finishPending || current.gameState == 5) vars.stopped = true;
    // Reset commits normal attempt/best-segment history before saving the chosen file.
    // No split is recorded for quitting, and game-over state 4 never enters here.
    if (current.gameState == 1 && timer.CurrentPhase != LiveSplit.Model.TimerPhase.NotRunning)
    {
        vars.timerModel.Reset();
        string temporary = null;
        try
        {
            string path = timer.Run.FilePath;
            if (String.IsNullOrWhiteSpace(path) ||
                !String.Equals(System.IO.Path.GetExtension(path), ".lss", StringComparison.OrdinalIgnoreCase))
                throw new Exception("Use Save Splits As to choose a .lss file before running.");
            path = System.IO.Path.GetFullPath(path);
            temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            using (var stream = System.IO.File.Create(temporary))
                new LiveSplit.Model.RunSavers.XMLRunSaver().Save(timer.Run, stream);
            if (System.IO.File.Exists(path))
                System.IO.File.Replace(temporary, path, path + ".bak");
            else System.IO.File.Move(temporary, path);
            vars.saveError = "";
        }
        catch (Exception ex)
        {
            vars.saveError = ex.Message;
            print("Menu reset: splits could not be saved; updated times remain in LiveSplit. " + ex.Message);
        }
        finally
        {
            if (temporary != null && System.IO.File.Exists(temporary))
            {
                try { System.IO.File.Delete(temporary); } catch { }
            }
        }
    }
    if (vars.stopped && timer.CurrentPhase == LiveSplit.Model.TimerPhase.Running)
        vars.timerModel.Pause();
    // Seeing the menu arms automatic start; attaching mid-level never starts a run.
    if (current.gameState == 1) vars.ready = true;
}

start
{
    bool eligible = !vars.stopped && vars.ready && old.gameState != 2 && current.gameState == 2
        && ((current.mode == 1 && (current.level & 0xFFFF) == 0
             && (current.level >> 16) >= 1 && (current.level >> 16) <= 10)
         || (current.mode == 0 && (current.level & 0xFFFF) >= 1
             && (current.level & 0xFFFF) <= 5
             && (current.level >> 16) >= 1 && (current.level >> 16) <= 4));
    if (!eligible || !settings.StartEnabled) return false;
    return true;
}

onStart
{
    vars.stopped = false;
    vars.finishPending = false;
    vars.completed.Clear();
    vars.ready = false;
}

onReset
{
    vars.stopped = false;
    vars.finishPending = false;
    vars.completed.Clear();
    vars.ready = false;
}

split
{
    if (vars.stopped) return false;
    int world = (int)(current.level & 0xFFFF);
    int level = (int)(current.level >> 16);
    bool valid = (current.mode == 1 && world == 0 && level >= 1 && level <= 10)
        || (current.mode == 0 && world >= 1 && world <= 5 && level >= 1 && level <= 4);
    if (valid && old.gameState == 2 && current.gameState == 3
        && old.level == current.level && old.mode == current.mode
        && vars.completed.Add(current.level))
    {
        // Stop at the final platform, without waiting for Continue/victory loading.
        vars.finishPending = (current.mode == 1 && level == 10)
            || (current.mode == 0 && world == 5 && level == 4);
        return true;
    }
    return false;
}

onSplit
{
    if (vars.finishPending)
    {
        vars.stopped = true;
        if (timer.CurrentPhase == LiveSplit.Model.TimerPhase.Running)
            vars.timerModel.Pause();
    }
}

isLoading
{
    // Game Time is real elapsed level time. Results/menu/next-level loading are removed.
    // In-level pause, death and respawn time remain counted.
    int world = (int)(current.level & 0xFFFF);
    int level = (int)(current.level >> 16);
    bool valid = (current.mode == 1 && world == 0 && level >= 1 && level <= 10)
        || (current.mode == 0 && world >= 1 && world <= 5 && level >= 1 && level <= 4);
    return vars.stopped || current.gameState != 2 || !valid;
}
