if VERSION>=v"1.4" && Sys.isapple() && !(haskey(ENV, "DOCUMENTER_KEY"))
    error("""Your Julia version is ≥1.4, and your operation system is MacOSX. 
Currently, there is a compatibility issue for this combination. 
Please downgrade your Julia version.""")
end

if haskey(ENV, "MANUAL") && ENV["MANUAL"]=="1" 
    error("""****** You indicated you want to build ADCME package manually. 
To this end, you need to create a dependency file 
$(joinpath(@__DIR__, "deps.jl"))
and populate it with appropriate binary locations. 
--------------------------------------------------------------------------------------------
BINDIR = ""
LIBDIR = ""
TF_INC = ""
TF_ABI = ""
EIGEN_INC = ""
CC = ""
CXX = ""
CMAKE = ""
MAKE = ""
GIT = ""
PYTHON = ""
TF_LIB_FILE = ""
LIBCUDA = ""
CUDA_INC = ""
__STR__ = join([BINDIR,LIBDIR,TF_INC,TF_ABI,EIGEN_INC,CC,CXX,CMAKE,MAKE,GIT,PYTHON,TF_LIB_FILE,LIBCUDA,CUDA_INC], ";")
--------------------------------------------------------------------------------------------
""")
end




@info " ########### Install Tensorflow Dependencies  ########### "
push!(LOAD_PATH, "@stdlib")
using Pkg
using Conda

if haskey(ENV, "FORCE_INSTALL_TF") && ENV["FORCE_INSTALL_TF"]=="1" && "adcme" in Conda._installed_packages()
    Conda.rm("adcme")
end

if !("adcme" in Conda._installed_packages())
    Conda.add("adcme", channel="kailaix")
end

ZIP = joinpath(Conda.BINDIR, "zip")
UNZIP = joinpath(Conda.BINDIR, "unzip")
GIT = "LibGit2"
PYTHON = joinpath(Conda.BINDIR, "python")
@info " ########### Check Python Version  ########### "

!haskey(Pkg.installed(), "PyCall") && Pkg.add("PyCall")
ENV["PYTHON"]=PYTHON
Pkg.build("PyCall")
using PyCall
@info """
PyCall Python version: $(PyCall.python)
Conda Python version: $PYTHON
"""

@info " ########### Preparing environment for custom operators ########### "
tf = pyimport("tensorflow")
core_path = abspath(joinpath(tf.sysconfig.get_compile_flags()[1][3:end], ".."))
lib = readdir(core_path)
TF_LIB_FILE = joinpath(core_path,lib[findall(occursin.("libtensorflow_framework", lib))[end]])
TF_INC = tf.sysconfig.get_compile_flags()[1][3:end]
TF_ABI = tf.sysconfig.get_compile_flags()[2][end:end]

@info " ########### Preparing Environment for Custom Operators ########### "
LIBDIR = "$(Conda.LIBDIR)/Libraries"

if !isdir(LIBDIR)
    @info "Downloading dependencies to $LIBDIR..."
    mkdir(LIBDIR)
end

if !isfile("$LIBDIR/eigen.zip")
    download("http://bitbucket.org/eigen/eigen/get/3.3.7.zip","$LIBDIR/eigen.zip")
end

if !isdir("$LIBDIR/eigen3")    
    run(`$UNZIP -qq $LIBDIR/eigen.zip`)
    mv("eigen-eigen-323c052e1731", "$LIBDIR/eigen3", force=true)
end


@info " ########### GPU Dependencies ########### "
LIBCUDA = ""
CUDA_INC = ""
if haskey(ENV, "GPU") && ENV["GPU"]=="1" && !(Sys.isapple())
    try 
        run(`which nvcc`)
    catch
        error("""You specified ENV["GPU"]=1 but nvcc cannot be found (`which nvcc`) failed.
Make sure `nvcc` is available.""")
    end
    s = join(readlines(pipeline(`nvcc --version`)), " ")
    ver = match(r"V(\d+\.\d)", s)[1]
    if ver[1:2]!="10"
        error("TensorFlow backend of ADCME requires CUDA 10.0. But you have CUDA $ver")
    end
    if ver[1:4]!="10.0"
        @warn("TensorFlow is compiled using CUDA 10.0, but you have CUDA $ver. This might cause some problems.")
    end

    if !("adcme-gpu" in Conda._installed_packages())
        Conda.add("adcme-gpu", channel="kailaix")
    end
    
    pkg_dir = joinpath(Conda.ROOTENV, "pkgs/")
    files = readdir(pkg_dir)
    libpath = filter(x->startswith(x, "cudatoolkit") && isdir(joinpath(pkg_dir,x)), files)
    if length(libpath)==0
        @warn "cudatoolkit* not found in $pkg_dir"
    elseif length(libpath)>1
        @warn "more than 1 cudatoolkit found, use $(libpath[1]) by default"
    end

    if length(libpath)>=1
        LIBCUDA = joinpath(pkg_dir, libpath[1], "lib")
    end
    

    libpath = filter(x->startswith(x, "cudnn") && isdir(joinpath(pkg_dir,x)), files)
    if length(libpath)==0
        @warn "cudnn* not found in $pkg_dir"
    elseif length(libpath)>1
        @warn "more than 1 cudatoolkit found, use $(libpath[1]) by default"
    end

    if length(libpath)>=1
        LIBCUDA = LIBCUDA*":"*joinpath(pkg_dir, libpath[1], "lib")
        @info " ########### CUDA include headers  ########### "
        cudnn = joinpath(pkg_dir, libpath[1], "include", "cudnn.h")
        cp(cudnn, joinpath(TF_INC, "cudnn.h"), force=true)
    end

    NVCC = readlines(pipeline(`which nvcc`))[1]
    CUDA_INC = joinpath(splitdir(splitdir(NVCC)[1])[1], "include")

end

@info """ ########### Write Dependency Files  ########### """

s = ""
t = []
function adding(k, v)
    global s 
    s *= "$k = \"$v\"\n"
    push!(t, "$k")
end
adding("BINDIR", Conda.BINDIR)
adding("LIBDIR", Conda.LIBDIR)
adding("TF_INC", TF_INC)
adding("TF_ABI", TF_ABI)
adding("EIGEN_INC", joinpath(Conda.LIBDIR,"Libraries"))
if Sys.isapple()
    adding("CC", joinpath(Conda.BINDIR, "clang"))
    adding("CXX", joinpath(Conda.BINDIR, "clang++"))
elseif Sys.islinux()
    adding("CC", joinpath(Conda.BINDIR, "x86_64-conda_cos6-linux-gnu-gcc"))
    adding("CXX", joinpath(Conda.BINDIR, "x86_64-conda_cos6-linux-gnu-g++"))
else
    adding("CC", joinpath(Conda.BINDIR, ""))
    adding("CXX", joinpath(Conda.BINDIR, ""))
end
adding("CMAKE", joinpath(Conda.BINDIR, "cmake"))
adding("MAKE", joinpath(Conda.BINDIR, "make"))
adding("GIT", GIT)
adding("PYTHON", PyCall.python)
adding("TF_LIB_FILE", TF_LIB_FILE)
adding("LIBCUDA", LIBCUDA)
adding("CUDA_INC", CUDA_INC)

t = "join(["*join(t, ",")*"], \";\")"
s *= "__STR__ = $t"
open("deps.jl", "w") do io 
    write(io, s)
end

@info """ ########### Finished: $(abspath("deps.jl"))  ########### """

