# PythonPkg.jl

One place to manage all the Python dependencies for your Julia project.

- Package-management with either `pip` or `conda` (or both).
- Installs package into Python virtual environments, or Conda environments, or
  even your system installation (not recommended).
- By default creates a Julia-project-specific environment, so dependencies are isolated.
  You can instead use a pre-existing environment, or use the root environment from Conda.jl.
- If PyCall is installed, will by default operate in PyCall-compatibility mode, meaning it
  will use whatever environment PyCall is set to use.
- Dependencies are declared at run-time, which is more flexible than e.g. CondaPkg.toml.

## API

See the docstrings for detailed information, including keyword arguments.

- `@require(pkg)` declares that the given Python package is needed.
- `@require_conda(pkg)` declares that the given Conda package is needed.
- `@require_conda_channel(channel)` declares that the given Conda channel is needed.
- `@require_nothing()` removes all requirements associated to the Julia project which made the call.
- `using_conda()` returns true if Conda requirements won't be ignored (because you are in a pip-only environment).
- `resolve()` installs any required packages.
- `which(progname)` returns the full path to the given program in the environment.
- `which_python()` returns the full path to the Python executable.
- `which_python_home()` returns the `PYTHONHOME` setting for the environment, if non-default.
- `setenv(cmd)` like `Base.setenv` but applies the Python environment.
- `run(cmd)` runs `cmd` in the environment, shorthand for `Base.run(PythonPkg.setenv(cmd))`.
- `activate!() do ... end` activate the environment, run the content of the `do` block, then deactivate.
- `status()` print out the status of all required packages.

Requirements are saved with an environment, so if you don't change environment then you
don't need to re-declare dependencies, they will be restored when Julia is started.

It is recorded which Julia package made each requirement. If the same package makes a new
requirement on the same Python package, the requirement is replaced. You can use
`@require_nothing()` to erase all requirements

## Examples

### Interactive usage

```julia
using PythonPkg
PythonPkg.@require("cowsay")
PythonPkg.run(`python -m cowsay moooooo`)
```

This will install the Python `cowsay` package, then run it to print out a cow saying moo.

Now if you restart Julia, you can do
```julia
using PythonPkg
PythonPkg.run(`python -m cowsay moooooo`)
```
and it will still work - the requirement on `cowsay` was remembered!

### In packages

```julia
module CowSay

using PythonPkg

function __init__()
    PythonPkg.@require_nothing()
    PythonPkg.@require("cowsay", version="~=5.0")
end

function cowsay(msg="moo")
    PythonPkg.run(`python -m cowsay $msg`)
    return
end

end
```

This is a minimal example of a module using PythonPkg.

Requirements are declared in the `__init__()` function. This uses `@require_nothing` to
erase any other requirements made by earlier versions of your package, to ensure nothing
unneeded is installed.

Ideally do not call `PythonPkg.resolve()` (or any other function which causes a resolve) in
the `__init__()` function. This means that all the packages being used can declare their
dependencies before resolving, and therefore PythonPkg only actually needs to install
anything once.
