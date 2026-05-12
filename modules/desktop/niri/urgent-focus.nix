# Listens to niri's IPC event stream and focuses any window that requests
# attention (xdg-activation -> niri urgency hint). Side effect: focusing a
# window switches to its workspace, which is exactly what we want when e.g.
# clicking a link in chat opens a tab in a browser on another workspace.
{ python3
, writeText
, writeShellScriptBin
}:

let
  scriptContent = writeText "niri-urgent-focus.py" ''
    import json
    import logging
    import os
    from pathlib import Path
    from socket import AF_UNIX, SHUT_WR, socket
    import sys
    from time import sleep


    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    log_path = Path(runtime_dir) / "niri-urgent-focus.log"

    logging.basicConfig(
        filename=log_path,
        encoding="utf-8",
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    logger = logging.getLogger(__name__)


    def send(request):
        niri_socket_path = os.environ.get("NIRI_SOCKET")
        if not niri_socket_path:
            logger.error("NIRI_SOCKET environment variable is not set")
            return

        with socket(AF_UNIX) as niri_socket:
            niri_socket.connect(niri_socket_path)
            f = niri_socket.makefile("rw")
            f.write(json.dumps(request) + "\n")
            f.flush()


    def focus(window_id: int):
        logger.info(f"focusing urgent window id={window_id}")
        send({"Action": {"FocusWindow": {"id": window_id}}})


    def main():
        logger.info("urgent-focus started")

        niri_socket = socket(AF_UNIX)
        niri_socket.connect(os.environ["NIRI_SOCKET"])
        f = niri_socket.makefile("rw")

        f.write('"EventStream"\n')
        f.flush()
        niri_socket.shutdown(SHUT_WR)

        for line in f:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue

            if changed := event.get("WindowUrgencyChanged"):
                if changed.get("urgent") and changed.get("id") is not None:
                    focus(int(changed["id"]))


    if __name__ == "__main__":
        while True:
            try:
                main()
            except KeyboardInterrupt:
                logger.info("stopped by CTRL+C")
                sys.exit(0)
            except Exception as err:
                logger.error(f"error: {err}, restarting in 5s")
                sleep(5.0)
  '';
in
writeShellScriptBin "niri-urgent-focus" ''
  exec ${python3}/bin/python ${scriptContent} "$@"
''
