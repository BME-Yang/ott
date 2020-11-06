classdef FieldVector < double
% Base class for classes encapsulating field vector data.
%
% Properties (possibly computed)
%
% Methods
%   - plus, minus, uminus, times, mtimes, rdivide, mrdivide
%   - sum     -- Add field vector components
%   - vxyz    -- Data in Cartesian coordinates
%   - vrtp    -- Data in Spherical coordinates

% Copyright 2020 Isaac Lenton
% This file is part of OTT, see LICENSE.md for information about
% using/distributing this file.

  methods (Access=protected)
    function field = FieldVector(vec, pos)
      % Construct a new FieldVector instance
      %
      % Usage
      %   field = FieldVector(vec, pos)
      %
      %   field = FieldVector([vec; pos])
      %
      % Parameters
      %   - vec (3xN numeric) -- Field vectors
      %
      %   - pos (3xN numeric) -- Coordinate locations (optional).
      %     If omitted, these are not stored, defaults to [0;0;0] when used.

      if nargin == 2
        data = [vec; pos];
      else
        data = vec;
      end

      assert(any(size(data, 1) == [3, 6]), ...
        'First dimension of data [vec; pos] must be 3 or 6');
      field = field@double(data);
    end
  end

  methods
    function fv = vxyz(fv, varargin)
      % Get Cartesian field vector instance

      if ~isa(fv, 'ott.utils.FieldVectorCart')
        fv = ott.utils.FieldVectorCart(fv);
      end

      % Get only vector component
      sz = size(fv);
      fv = reshape(double(fv(1:3, :)), [3, sz(2:end)]);

      % Interpret additional arguments as subscripts
      if nargin >= 2
        fv = fv(varargin{:});
      end
    end

    function fv = vrtp(fv, varargin)
      % Get Spherical field vector instance

      if ~isa(fv, 'ott.utils.FieldVectorSph')
        fv = ott.utils.FieldVectorSph(fv);
      end

      % Get only vector component
      sz = size(fv);
      fv = reshape(double(fv(1:3, :)), [3, sz(2:end)]);

      % Interpret additional arguments as subscripts
      if nargin >= 2
        fv = fv(varargin{:});
      end
    end

    function out = sum(vec, dim)
      % Sum field vectors along specified dimension
      %
      % Usage
      %   fv = sum(fv, dim)
      %
      % If dimension is 1, returns a double.  Otherwise returns a
      % field vector.

      out = sum(vec.vxyz, dim);

      if size(out, 1) == 3
        out = ott.utils.FieldVectorCart(out);
      end
    end

    function vec = plus(v1, v2)
      % Addition of field vectors
      %
      % Usage
      %   fv = fv1 + fv2 -- Adds field vectors in Cartesian basis.
      %   Resulting field vector object has no location data.
      %
      %   s = fv1 + s2, and s = s1 + fv1 -- Add non-field vector types.
      %   Results in a double or other non-field vector type.

      if isa(v1, 'ott.utils.FieldVector') && isa(v2, 'ott.utils.FieldVector')
        vec = ott.utils.FieldVectorCart(v1.vxyz + v2.vxyz);
      elseif isa(v1, 'ott.utils.FieldVector')
        vec = v1.vxyz + v2;
      else
        vec = v1 + v2.vxyz;
      end
    end

    function vec = minus(v1, v2)
      % Subtraction of field vectors
      %
      % Usage
      %   fv = fv1 - fv2 -- Adds field vectors in Cartesian basis.
      %   Resulting field vector object has no location data.
      %
      %   s = fv1 - s2, and s = s1 - fv1 -- Add non-field vector types.
      %   Results in a double or other non-field vector type.

      if isa(v1, 'ott.utils.FieldVector') && isa(v2, 'ott.utils.FieldVector')
        vec = ott.utils.FieldVectorCart(v1.vxyz - v2.vxyz);
      elseif isa(v1, 'ott.utils.FieldVector')
        vec = v1.vxyz - v2;
      else
        vec = v1 - v2.vxyz;
      end
    end

    function vec = uminus(vec)
      % Unitary minus of field vector
      %
      % Usage
      %   vec = -vec -- Negates vector components.  Leaves location unchanged.

      sz = size(vec);
      vec(1:3, :) = -double(vec(1:3, :));
      vec = reshape(vec, sz);
    end

    function vec = times(v1, v2)
      % Multiplication of field vectors
      %
      % Usage
      %   fv = fv1 .* fv2 -- Times field vectors in Cartesian basis.
      %   Resulting field vector object has no location data.
      %
      %   fv = fv1 .* s2, and fv = s1 .* fv1 -- Scale field vector.
      %   Resulting field vector has same location as original.

      if isa(v1, 'ott.utils.FieldVector') && isa(v2, 'ott.utils.FieldVector')
        vec = ott.utils.FieldVectorCart(v1.vxyz .* v2.vxyz);
      elseif isa(v1, 'ott.utils.FieldVector')
        sz = size(v1);
        v1(1:3, :) = double(v1(1:3, :)) .* v2;
        vec = reshape(v1, sz);
      else
        sz = size(v2);
        v2(1:3, :) = v1 .* double(v2(1:3, :));
        vec = reshape(v2, sz);
      end
    end

    function vec = mtimes(v1, v2)
      % Matrix and scalar multiplication
      %
      % Usage
      %   s = M * fv -- Matrix multiplication.  M should be nx3.
      %   First gets the Cartesian field vectors.
      %
      %   fv = fv1 * s2, and fv = s1 * fv1 -- Scale field vector.
      %   Same behaviour as .* operation.

      if ~isa(v1, 'ott.utils.FieldVector') && ~isscalar(v1) ...
          && isa(v2, 'ott.utils.FieldVector')
        vec = v1 * v2.vxyz;
      else
        vec = v1 .* v2;
      end
    end

    function vec = rdivide(v1, s)
      % Scalar division
      %
      % Usage
      %   fv = fv ./ s -- Divide field vector values by scalar.

      assert(isa(v1, 'ott.utils.FieldVector'), ...
          'First argument must be a field vector');

      sz = size(v1);
      v1(1:3, :) = double(v1(1:3, :)) ./ s;
      vec = reshape(v1, sz);
    end

    function vec = mrdivide(v1, s)
      % Scalar division
      %
      % Usage
      %   fv = fv / s -- uses same behaviour as ./ operator.

      vec = v1 ./ s;
    end
  end
end
