# /etc/nixos/carousel.nix

{ config, lib, pkgs, ... }:

let
  taskBin = "${pkgs.taskwarrior3}/bin/task";

  taskCarousel = pkgs.writers.writePython3Bin "task-carousel" {
    libraries = [ ];
    doCheck = false;
  } ''
    import sys
    import json
    import random
    import subprocess
    from datetime import datetime

    PROJECTS_CONFIG = {
        "technical": 5,
        "system": 4,
        "yuko": 4,
        "life": 3,
        "radiant": 2,
        "re-l": 2,
    }

    def run_cmd(args):
        # Point to the local task data location used by the server/system service if needed, 
        # or let it fallback to default environment paths.
        result = subprocess.run(["${taskBin}", "rc.confirmation=no"] + args, capture_output=True, text=True)
        return result.stdout.strip()

    def main():
        today_str = datetime.now().strftime("%Y-%m-%d")
        status = run_cmd(["rc.verbose=nothing", "rc.hooks=off", "+carousel_tracker", "export"])
        
        if status:
            try:
                tasks = json.loads(status)
                if tasks:
                    task_list = tasks if isinstance(tasks, list) else [tasks]
                    for tracker in task_list:
                        if tracker.get("description") == f"Carousel Ran: {today_str}":
                            sys.exit(0)
                        else:
                            run_cmd(["rc.hooks=off", str(tracker["uuid"]), "delete"])
            except Exception:
                pass

        project_names = list(PROJECTS_CONFIG.keys())
        project_weights = list(PROJECTS_CONFIG.values())
        selected_project = random.choices(project_names, weights=project_weights, k=1)[0]

        run_cmd(["rc.hooks=off", "add", f"=^-.-^= Neural Ordinance: {selected_project} project", "due:today", "+inbox", f"project:{selected_project}"])
        run_cmd(["rc.hooks=off", "add", f"Carousel Ran: {today_str}", "+carousel_tracker", "status:completed"])

    if __name__ == "__main__":
        main()
  '';
in
{
  # System-wide timer to drop the daily Neural Ordinance automatically
  systemd.timers.taskwarrior-carousel = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "08:00:00";
      Persistent = true;
    };
  };

  systemd.services.taskwarrior-carousel = {
    script = ''
      ${taskCarousel}/bin/task-carousel
    '';
    serviceConfig = {
      Type = "oneshot";
      # Run as your user or the service user that owns the task data
      User = "trynn"; 
    };
  };
}
