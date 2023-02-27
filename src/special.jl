# special Toeplitz types that can be represented by a single vector
# Symmetric, Circulant, LowerTriangular, UpperTriangular
for TYPE in (:SymmetricToeplitz, :Circulant, :LowerTriangularToeplitz, :UpperTriangularToeplitz)
    @eval begin
        struct $TYPE{T<:Number} <: AbstractToeplitz{T}
            v::AbstractVector{T}
        end

        convert(::Type{AbstractToeplitz{T}}, A::$TYPE) where {T} = convert($TYPE{T},A)
        convert(::Type{$TYPE{T}}, A::$TYPE) where {T} = $TYPE(convert(AbstractVector{T},A.v))

        function size(A::$TYPE, dim::Int)
            if dim < 1
                error("arraysize: dimension out of range")
            end
            return dim < 3 ? length(A.v) : 1
        end
        
        adjoint(A::$TYPE) = transpose(conj(A))
        (*)(scalar::Number, C::$TYPE) = $TYPE(scalar * C.v)
        (*)(C::$TYPE, scalar::Number) = $TYPE(C.v * scalar)
        (==)(A::$TYPE,B::$TYPE) = A.v==B.v

        function copyto!(A::$TYPE,B::$TYPE)
            copyto!(A.v,B.v)
            A
        end
        similar(A::$TYPE, T::Type) = $TYPE{T}(similar(A.v, T))
    end
    for fun in (:lmul!,)
        @eval begin
            function $fun(x::Number, A::$TYPE)
                $fun(x,A.v)
                A
            end
        end
    for fun in (:fill!, :rmul!)
        @eval begin
            function $fun(A::$TYPE, x::Number)
                $fun(A.v,x)
                A
            end
        end
    end
    for fun in (:zero, :conj, :copy, :-, :real, :imag)
        @eval begin
            $fun(A::$TYPE) = $TYPE($fun(A.v))
        end
    end
    for fun in (:iszero,)
        @eval begin
            $fun(A::$TYPE) = $fun(A.v)
        end
    end
    for op in (:+, :-)
        @eval begin
            $op(A::$TYPE,B::$TYPE) = $TYPE($op(A.v,B.v))
        end
    end
    for TY in (:AbstractVector, :AbstractMatrix, :AbstractToeplitz)
        @eval begin
            $TYPE(v::$TY) = $TYPE{eltype(v)}(v)
        end
    end
end
TriangularToeplitz{T}=Union{UpperTriangularToeplitz{T},LowerTriangularToeplitz{T}}

# vc and vr
function getproperty(A::SymmetricToeplitz, s::Symbol)
    if s==:vc || s==:vr
        getfield(A,:v)
    else
        getfield(A,s)
    end
end
function getproperty(A::Circulant, s::Symbol)
    if s==:vc
        getfield(A,:v)
    elseif s==:vr
        _circulate(getfield(A,:v))
    else
        getfield(A,s)
    end
end
function getproperty(A::LowerTriangularToeplitz, s::Symbol)
    if s==:vc
        getfield(A,:v)
    elseif s==:vr
        _firstnonzero(getfield(A,:v))
    elseif s==:uplo
        :L
    else
        getfield(A,s)
    end
end
function getproperty(A::UpperTriangularToeplitz, s::Symbol)
    if s==:vr
        getfield(A,:v)
    elseif s==:vc
        _firstnonzero(getfield(A,:v))
    elseif s==:uplo
        :U
    else
        getfield(A,s)
    end
end

_circulate(v::AbstractVector) = vcat(v[1],v[end:-1:2])
_firstnonzero(v::AbstractVector) = vcat(v[1],zero(view(v,2:lastindex(v))))

# transpose
transpose(A::SymmetricToeplitz) = A
transpose(A::Circulant) = Circulant(A.vr)
transpose(A::LowerTriangularToeplitz) = UpperTriangularToeplitz(A.v)
transpose(A::UpperTriangularToeplitz) = LowerTriangularToeplitz(A.v)

# getindex
function getindex(A::SymmetricToeplitz, i::Integer, j::Integer)
    @boundscheck checkbounds(A,i,j)
    return A.v[abs(i - j) + 1]
end
function getindex(C::Circulant, i::Integer, j::Integer)
    @boundscheck checkbounds(C,i,j)
    d = i - j
    return C.v[d < 0 ? size(C,1)+d+1 : d+1]
end
function getindex(A::LowerTriangularToeplitz{T}, i::Integer, j::Integer) where T
    @boundscheck checkbounds(A,i,j)
    return i >= j ? A.v[i - j + 1] : zero(T)
end
function getindex(A::UpperTriangularToeplitz{T}, i::Integer, j::Integer) where T
    @boundscheck checkbounds(A,i,j)
    return i <= j ? A.v[j - i + 1] : zero(T)
end

# constructors
function Circulant{T}(v::AbstractVector, uplo::Symbol) where T<:Number
    if uplo == :L
        Circulant{T}(v)
    elseif uplo == :U
        Circulant{T}(_circulate(v))
    else
        throw(ArgumentError("expected :L or :U; got $uplo."))
    end
end
Circulant(v::AbstractVector, uplo::Symbol) = Circulant{eltype(v)}(v,uplo)
# from AbstractMatrix, AbstractToeplitz
function Circulant{T}(A::AbstractMatrix, uplo::Symbol = :L) where T<:Number
    checksquare(A)
    if uplo == :L
        Circulant{T}(_vc(A), uplo)
    elseif uplo == :U
        Circulant{T}(_vr(A), uplo)
    else
        throw(ArgumentError("expected :L or :U; get $uplo."))
    end
end
Circulant(A::AbstractMatrix, uplo::Symbol) = Circulant{eltype(A)}(A,uplo)
function SymmetricToeplitz{T}(A::AbstractMatrix, uplo::Symbol = :U) where T<:Number
    checksquare(A)
    if uplo == :L
        SymmetricToeplitz{T}(_vc(A))
    elseif uplo == :U
        SymmetricToeplitz{T}(_vr(A))
    else
        throw(ArgumentError("expected :L or :U; got $uplo."))
    end
end
SymmetricToeplitz(A::AbstractMatrix, uplo::Symbol) = SymmetricToeplitz{eltype(A)}(A,uplo)
Symmetric(A::AbstractToeplitz, uplo::Symbol = :U) = SymmetricToeplitz(A,uplo)

function UpperTriangularToeplitz{T}(A::AbstractMatrix) where T<:Number 
    checksquare(A)
    UpperTriangularToeplitz{T}(_vr(A))
end
function LowerTriangularToeplitz{T}(A::AbstractMatrix) where T<:Number 
    checksquare(A)
    LowerTriangularToeplitz{T}(_vc(A))
end
_toeplitztype(s::Symbol) = Symbol(s,"Toeplitz")
for TYPE in (:UpperTriangular, :LowerTriangular)
    @eval begin
        $TYPE{T}(A::AbstractToeplitz) where T<:Number = $(_toeplitztype(TYPE)){T}(A)
        $TYPE(A::AbstractToeplitz) = $TYPE{eltype(A)}(A)
        convert(::Type{TriangularToeplitz{T}},A::$(_toeplitztype(TYPE))) where T<:Number = convert($(_toeplitztype(TYPE)){T},A)
    end
end

# Triangular
for TYPE in (:AbstractMatrix, :AbstractVector)
    @eval begin
        TriangularToeplitz(A::$TYPE, uplo::Symbol) = TriangularToeplitz{eltype(A)}(A, uplo)
        function TriangularToeplitz{T}(A::$TYPE, uplo::Symbol) where T<:Number
            if uplo == :L
                LowerTriangularToeplitz{T}(A)
            elseif uplo == :U
                UpperTriangularToeplitz{T}(A)
            else
                throw(ArgumentError("expected :L or :U. got $uplo."))
            end
        end
    end
end

# Triangular
function _tridiff!(A::TriangularToeplitz, k::Integer)
    if k >= 0
        if isconcretetype(typeof(A.v))
            for i in k+2:lastindex(A.v)
                A.v[i] = zero(eltype(A))
            end
        else
            A.v=vcat(A.v[1:k+1], zero(A.v[k+2:end]))
        end
    else
        fill!(A,zero(eltype(A)))
    end
    A
end
tril!(A::UpperTriangularToeplitz, k::Integer) = _tridiff!(A,k)
triu!(A::LowerTriangularToeplitz, k::Integer) = _tridiff!(A,-k)

function _trisame!(A::TriangularToeplitz, k::Integer)
    if k < 0
        if isconcretetype(typeof(A.v))
            for i in 1:-k
                A.v[i]=zero(eltype(A))
            end
        else
            A.v=vcat(A.v[1:-k+1], zero(A.v[-k+2:end]))
        end
    end
    A
end
tril!(A::LowerTriangularToeplitz, k::Integer) = _trisame!(A,k)
triu!(A::UpperTriangularToeplitz, k::Integer) = _trisame!(A,-k)
