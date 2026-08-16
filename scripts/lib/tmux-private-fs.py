#!/usr/bin/env python3

import argparse
import json
import os
import stat
import sys
import uuid


def fail(message: str) -> None:
    raise RuntimeError(message)


def private_directory(fd: int, path: str) -> None:
    info = os.fstat(fd)
    if not stat.S_ISDIR(info.st_mode):
        fail(f"not a directory: {path}")
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        fail(f"not a private directory: {path}")


def private_file(fd: int, path: str) -> None:
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode):
        fail(f"not a regular file: {path}")
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
        fail(f"not a private file: {path}")


def open_root(root: str) -> int:
    return os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)


def components(relative: str) -> list[str]:
    parts = relative.split("/")
    if not relative or any(part in {"", ".", ".."} for part in parts):
        fail(f"unsafe relative path: {relative}")
    return parts


def open_parent(root_fd: int, relative: str, create: bool) -> tuple[int, str]:
    parts = components(relative)
    current = os.dup(root_fd)
    try:
        private_directory(current, "root")
        for part in parts[:-1]:
            try:
                next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=current)
            except FileNotFoundError:
                if not create:
                    raise
                os.mkdir(part, 0o700, dir_fd=current)
                next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=current)
            private_directory(next_fd, part)
            os.close(current)
            current = next_fd
        return current, parts[-1]
    except Exception:
        os.close(current)
        raise


def write_json(root: str, relative: str, document: str) -> None:
    json.loads(document)
    root_fd = open_root(root)
    try:
        parent_fd, name = open_parent(root_fd, relative, True)
        try:
            private_directory(parent_fd, relative)
            temporary = f".{name}.{uuid.uuid4().hex}.tmp"
            temp_fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=parent_fd)
            try:
                os.write(temp_fd, (document + "\n").encode())
                os.fsync(temp_fd)
                private_file(temp_fd, temporary)
            finally:
                os.close(temp_fd)
            try:
                existing = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent_fd)
            except FileNotFoundError:
                existing = None
            if existing is not None:
                try:
                    private_file(existing, relative)
                finally:
                    os.close(existing)
            os.replace(temporary, name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
            final_fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent_fd)
            try:
                private_file(final_fd, relative)
            finally:
                os.close(final_fd)
            os.fsync(parent_fd)
        finally:
            os.close(parent_fd)
    finally:
        os.close(root_fd)


def publish_directory(root: str, relative: str, owner: str) -> None:
    json.loads(owner)
    root_fd = open_root(root)
    try:
        parent_fd, name = open_parent(root_fd, relative, True)
        try:
            private_directory(parent_fd, relative)
            temporary = f".{name}.{uuid.uuid4().hex}.tmp"
            try:
                os.mkdir(temporary, 0o700, dir_fd=parent_fd)
                temp_fd = os.open(temporary, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
                try:
                    private_directory(temp_fd, temporary)
                    owner_fd = os.open("owner.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=temp_fd)
                    try:
                        os.write(owner_fd, (owner + "\n").encode())
                        os.fsync(owner_fd)
                    finally:
                        os.close(owner_fd)
                    os.fsync(temp_fd)
                finally:
                    os.close(temp_fd)
                try:
                    os.rename(temporary, name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
                except OSError as error:
                    if error.errno in {17, 66}:
                        raise FileExistsError(name) from error
                    raise
                os.fsync(parent_fd)
            except Exception:
                try:
                    cleanup_fd = os.open(temporary, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
                    try:
                        os.unlink("owner.json", dir_fd=cleanup_fd)
                    finally:
                        os.close(cleanup_fd)
                except Exception:
                    pass
                try:
                    os.rmdir(temporary, dir_fd=parent_fd)
                except Exception:
                    pass
                raise
        finally:
            os.close(parent_fd)
    finally:
        os.close(root_fd)


def move(root: str, source: str, destination: str) -> None:
    root_fd = open_root(root)
    try:
        source_parent, source_name = open_parent(root_fd, source, False)
        destination_parent, destination_name = open_parent(root_fd, destination, False)
        try:
            source_fd = os.open(source_name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=source_parent)
            try:
                private_file(source_fd, source)
            finally:
                os.close(source_fd)
            try:
                os.link(source_name, destination_name, src_dir_fd=source_parent, dst_dir_fd=destination_parent, follow_symlinks=False)
            except FileExistsError:
                fail(f"destination already exists: {destination}")
            os.unlink(source_name, dir_fd=source_parent)
            os.fsync(source_parent)
            if source_parent != destination_parent:
                os.fsync(destination_parent)
        finally:
            os.close(source_parent)
            os.close(destination_parent)
    finally:
        os.close(root_fd)


def complete_ack(root: str, source: str, destination: str) -> None:
    root_fd = open_root(root)
    try:
        source_parent, source_name = open_parent(root_fd, source, False)
        destination_parent, destination_name = open_parent(root_fd, destination, False)
        try:
            try:
                source_fd = os.open(source_name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=source_parent)
            except FileNotFoundError:
                source_fd = None
            try:
                destination_fd = os.open(destination_name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=destination_parent)
            except FileNotFoundError:
                destination_fd = None
            try:
                if source_fd is not None:
                    private_file(source_fd, source)
                if destination_fd is not None:
                    private_file(destination_fd, destination)
                if source_fd is None and destination_fd is None:
                    fail(f"acknowledgement source is unavailable: {source}")
                if source_fd is not None and destination_fd is None:
                    os.link(source_name, destination_name, src_dir_fd=source_parent, dst_dir_fd=destination_parent, follow_symlinks=False)
                    os.fsync(destination_parent)
                    if os.environ.get("LBWC_TMUX_FS_FAIL_AFTER_ACK_LINK") == "1":
                        fail("injected acknowledgement interruption after link")
                elif source_fd is not None and destination_fd is not None:
                    source_info = os.fstat(source_fd)
                    destination_info = os.fstat(destination_fd)
                    if (source_info.st_dev, source_info.st_ino) != (destination_info.st_dev, destination_info.st_ino):
                        fail(f"acknowledgement destination conflicts: {destination}")
                if source_fd is not None:
                    os.unlink(source_name, dir_fd=source_parent)
                    os.fsync(source_parent)
                os.fsync(destination_parent)
            finally:
                if source_fd is not None:
                    os.close(source_fd)
                if destination_fd is not None:
                    os.close(destination_fd)
        finally:
            os.close(source_parent)
            os.close(destination_parent)
    finally:
        os.close(root_fd)


def read_json(root: str, source: str) -> str:
    root_fd = open_root(root)
    try:
        parent_fd, name = open_parent(root_fd, source, False)
        try:
            source_fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent_fd)
            try:
                private_file(source_fd, source)
                document = os.read(source_fd, 1024 * 1024).decode()
                json.loads(document)
            finally:
                os.close(source_fd)
            return document
        finally:
            os.close(parent_fd)
    finally:
        os.close(root_fd)


def delete(root: str, relative: str) -> None:
    root_fd = open_root(root)
    try:
        parent_fd, name = open_parent(root_fd, relative, False)
        try:
            file_fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent_fd)
            try:
                private_file(file_fd, relative)
            finally:
                os.close(file_fd)
            os.unlink(name, dir_fd=parent_fd)
            os.fsync(parent_fd)
        finally:
            os.close(parent_fd)
    finally:
        os.close(root_fd)


def ensure_directory(path: str) -> None:
    created = False
    try:
        os.mkdir(path, 0o700)
        created = True
    except FileExistsError:
        created = False
    except OSError:
        fail(f"cannot create directory: {path}")
    try:
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError:
        fail(f"cannot inspect directory: {path}")
    try:
        if created:
            os.fchmod(fd, 0o700)
        private_directory(fd, path)
    finally:
        os.close(fd)


def check_directory(path: str) -> None:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError:
        fail(f"private directory is unavailable: {path}")
    try:
        private_directory(fd, path)
    finally:
        os.close(fd)


def check_directories(paths: list[str]) -> None:
    if not paths:
        fail("paths are required")
    for path in paths:
        check_directory(path)


def check_file(path: str) -> None:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        fail(f"private file is unavailable: {path}")
    try:
        private_file(fd, path)
    finally:
        os.close(fd)


def list_json(path: str) -> None:
    try:
        dir_fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError:
        fail(f"private directory is unavailable: {path}")
    try:
        private_directory(dir_fd, path)
        timed: list[tuple[int, str]] = []
        for name in os.listdir(dir_fd):
            if not name.endswith(".json") or name in {".", ".."} or "/" in name:
                continue
            try:
                file_fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dir_fd)
            except FileNotFoundError:
                continue
            try:
                private_file(file_fd, name)
                timed.append((os.fstat(file_fd).st_mtime_ns, name))
            finally:
                os.close(file_fd)
        timed.sort(reverse=True)
        for _, name in timed:
            print(name)
    finally:
        os.close(dir_fd)


def probe(root: str) -> None:
    root_fd = open_root(root)
    try:
        private_directory(root_fd, root)
        probe_name = f".probe.{uuid.uuid4().hex}"
        probe_fd = os.open(probe_name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=root_fd)
        os.close(probe_fd)
        os.unlink(probe_name, dir_fd=root_fd)
    finally:
        os.close(root_fd)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["write-json", "publish-directory", "move", "complete-ack", "read-json", "delete", "probe", "ensure-directory", "check-directory", "check-directories", "check-file", "list-json"])
    parser.add_argument("--root")
    parser.add_argument("--relative")
    parser.add_argument("--document")
    parser.add_argument("--source")
    parser.add_argument("--destination")
    parser.add_argument("--path")
    parser.add_argument("--paths", nargs="+")
    args = parser.parse_args()
    if args.command in {"ensure-directory", "check-directory", "check-directories", "check-file", "list-json"}:
        if args.command == "check-directories":
            if not args.paths:
                fail("--paths is required")
        elif not args.path:
            fail("--path is required")
    elif not args.root:
        fail("--root is required")
    if args.command == "write-json":
        write_json(args.root, args.relative, args.document)
    elif args.command == "publish-directory":
        publish_directory(args.root, args.relative, args.document)
    elif args.command == "move":
        move(args.root, args.source, args.destination)
    elif args.command == "complete-ack":
        complete_ack(args.root, args.source, args.destination)
    elif args.command == "read-json":
        sys.stdout.write(read_json(args.root, args.source))
    elif args.command == "delete":
        delete(args.root, args.relative)
    elif args.command == "ensure-directory":
        ensure_directory(args.path)
    elif args.command == "check-directory":
        check_directory(args.path)
    elif args.command == "check-directories":
        if not args.paths:
            fail("--paths is required")
        check_directories(args.paths)
    elif args.command == "check-file":
        check_file(args.path)
    elif args.command == "list-json":
        list_json(args.path)
    else:
        probe(args.root)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"tmux private fs: {error}", file=sys.stderr)
        sys.exit(1)
