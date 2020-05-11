classdef StarShape < ott.shapes.Shape & ott.shapes.utils.CoordsSph
% Abstract class for star shaped particles.
% Inherits from :class:`ott.shapes.Shape`.
%
% Abstract methods:
%   radii           Calculates the particle radii for angular coordinates
%   axialSymmetry   Returns x, y, z rotational symmetry (0 for infinite)
%   mirrorSymmetry  Returns x, y, z mirror symmetry

% This file is part of the optical tweezers toolbox.
% See LICENSE.md for information about using/distributing this file.

  methods (Abstract)
    radii(shape, theta, phi);
    axialSymmetry(shape);
  end

  methods

    function varargout = mirrorSymmetry(shape)
      % Return the mirror symmetry for the particle
      %
      % Tries to determine the objects mirror symmetry from the
      % axialSymmetry.  Should be overridden for more complex objects.

      % First calculate the axial symmetry
      axialSym = shape.axialSymmetry();
      orthSym = mod(axialSym, 2) == 0;
      mirrorSym = [ orthSym(2) | orthSym(3), ...
          orthSym(1) | orthSym(3), orthSym(1) | orthSym(2) ];

      if nargout == 1
        varargout{1} = mirrorSym;
      else
        varargout{1} = mirrorSym(1);
        varargout{2} = mirrorSym(2);
        varargout{3} = mirrorSym(3);
      end
    end

    function varargout = locations(shape, theta, phi)
      % LOCATIONS calculates Cartessian coordinate locations for points
      %
      % [x, y, z] = locations(theta, phi) calculates the Cartesian coordinates
      % for locations on the surface specified by polar angle theta [0, pi)
      % and azimuthal angle phi [0, 2*pi).
      %
      % xyz = locations(theta, phi) as above, but returns the output
      % into a Nx3 matrix [x, y, z].

      theta = theta(:);
      phi = phi(:);
      [theta,phi] = ott.utils.matchsize(theta,phi);

      [varargout{1:nargout}] = ott.utils.rtp2xyz(...
          shape.radii(theta, phi), theta, phi);
    end

    function varargout = surf(shape, varargin)
      % SURF generate a visualisation of the shape
      %
      % SURF(...) displays a visualisation of the shape in the current figure.
      %
      % [X, Y, Z] = surf() calculates the coordinates and arranges them
      % in a grid suitable for use with matlab surf function.
      %
      % Optional named arguments:
      %   position   [x;y;z]   offset for location of surface
      %   rotation   mat     rotation matrix to apply to surface
      %   points   { theta, phi }  specify points to use for surface
      %   npoints  [ntheta, nphi]  specify number of points in each direction
      %   axes       []        axis to place surface in (default: gca)
      %   surfoptions   {varargin} options to be passed to surf.

      p = inputParser;
      shape.surfAddArgs(p);
      p.parse(varargin{:});

      % Get the points to use for the surface
      if isempty(p.Results.points)

        % Get the size from the user inputs
        sz = p.Results.npoints;
        if numel(sz) == 1
          sz = [sz sz];
        end

        [theta, phi] = shape.angulargrid('full', true, 'size', sz);
      else
        theta = p.Results.points{1};
        phi = p.Results.points{2};

        if min(size(theta)) == 1 && min(size(phi)) == 1
          [phi, theta] = meshgrid(phi, theta);
        elseif size(theta) ~= size(phi)
          error('theta and phi must be vectors or matricies of the same size');
        end

        sz = size(theta);
      end

      % Calculate Cartesian coordinates
      [X, Y, Z] = shape.locations(theta, phi);

      % Reshape to desired shape and translate
      X = reshape(X, sz) + shape.position(1);
      Y = reshape(Y, sz) + shape.position(2);
      Z = reshape(Z, sz) + shape.position(3);

      % Complete the sphere (add the missing faces)
      X(:, end+1) = X(:, 1);
      Y(:, end+1) = Y(:, 1);
      Z(:, end+1) = Z(:, 1);

      % Draw the figure and handle rotations/translations
      [varargout{1:nargout}] = shape.surfCommon(p, sz, X, Y, Z);
    end

    function varargout = voxels(shape, spacing, varargin)
      % Generate an array of xyz coordinates for voxels inside the shape
      %
      % voxels(spacing) shows a visualisation of the shape with
      % circles placed at locations on a Cartesian grid.
      %
      % xyz = voxels(spacing) returns the voxel locations.
      %
      % Optional named arguments:
      %   - 'plotoptions'   Options to pass to the plot3 function
      %   - 'visualise'     Show the visualisation (default: nargout == 0)
      %   - origin (enum) -- Coordinate system origin.  Either 'world'
      %     or 'shape' for world coordinates or shape coordinates.
      %     Default: 'shape'.
      %   - even_range (logical) -- Ensure the number of dipoles along
      %     any axis is even, so to avoid 0.  For example:
      %     When true, a range could be ``[-1.5, -0.5, 0.5, 1.5]``.
      %     When false, a range might be ``[-1, 0, 1]``.
      %     Default: ``false``.

      p = inputParser;
      p.addParameter('plotoptions', {...
          'MarkerFaceColor', 'w', ...
          'MarkerEdgeColor', [.5 .5 .5], ...
          'MarkerSize', 20*spacing/shape.maxRadius});
      p.addParameter('visualise', nargout == 0);
      p.addParameter('origin', 'shape');
      p.addParameter('even_range', false);
      p.parse(varargin{:});

      % Calculate range of dipoles
      numr = ceil(shape.maxRadius / spacing);
      
      if p.Results.even_range
        % Add an extra point so we don't have a point around zero
        numr = numr + 0.5;
      end
      rrange = (-numr:numr)*spacing;

      % Generate the voxel grid
      [xx, yy, zz] = meshgrid(rrange, rrange, rrange);
      xyz = [xx(:) yy(:) zz(:)].';

      % Determine which points are inside
      mask = shape.insideXyz(xyz, 'origin', 'shape');
      xyz(:, ~mask) = [];

      % Translate to world origin
      if strcmpi(p.Results.origin, 'world')
        xyz = xyz + shape.position;
      elseif strcmpi(p.Results.origin, 'shape')
        % Nothing to do
      else
        error('origin must be ''world'' or ''shape''');
      end

      % Visualise the result
      if p.Results.visualise
        plot3(xyz(1,:), xyz(2,:), xyz(3,:), 'o', p.Results.plotoptions{:});
        axis equal
        title(['spacing = ' num2str(spacing) ', N = ' int2str(sum(mask))])
      end

      % Assign output
      if nargout ~= 0
        varargout = {xyz};
      end
    end

    function [xyz, nxyz, dA] = surfPoints(shape, varargin)
      % Calculate surface points for surface integration
      %
      % Usage
      %   [xyz, nxyz, dA] = shape.surfPoints(...)

      % Get an angular grid for the shape
      [r, t, p] = shape.angulargrid('full', true);
      rtp = [r(:), t(:), p(:)].';
      xyz = ott.utils.rtp2xyz(rtp);

      % Calculate normals at these locations
      nxyz = shape.normalsRtp(rtp);

      % Calculate surface area for points
      % Assumption: The surface is close to spherical
      % Assumption: the angular grid is equally spaced
      dtheta = sort(unique(rtp(2, :)));
      dtheta = dtheta(2) - dtheta(1);
      dphi = sort(unique(rtp(3, :)));
      dphi = dphi(2) - dphi(1);
      dA = rtp(1, :).^2 .* sin(rtp(2, :)) .* dphi .* dtheta;

    end

    function varargout = angulargrid(shape, varargin)
      % ANGULARGRID calculate the angular grid and radii for the shape
      %
      % This is the default function with no symmetry optimisations.
      %
      % [theta, phi] = ANGULARGRID(Nmax) gets the default angular
      % grid for the particle.
      %
      % rtp = ANGULARGRID(Nmax) or [r, theta, phi] = ANGULARGRID(Nmax)
      % calculate the radii for the locations theta, phi.
      %
      % ANGULARGRID() uses a default Nmax of 100.
      %
      % ANGULARGRID(..., 'full', full) calculates
      % an angular grid over the full sphere.
      %
      % ANGULARGRID(..., 'size', [ntheta, nphi]) uses ntheta and
      % nphi instead of Nmax for angular grid.

      p = inputParser;
      p.addOptional('Nmax', 100);
      p.addParameter('full', false);    % Not used
      p.addParameter('size', []);    % Not used
      p.parse(varargin{:});

      if isempty(p.Results.size)

        % OTTv1 used something like the following, use it for now
        % until we can think of something better.

        ntheta = 2*(p.Results.Nmax + 2);
        nphi = 3*(p.Results.Nmax + 2) + 1;

        if ~p.Results.full

          [~, ~, z_axial_symmetry] = shape.axialSymmetry();
          if z_axial_symmetry == 0
            ntheta = 4*(p.Results.Nmax + 2);
            nphi = 1;
          else
            nphi = round(nphi / z_axial_symmetry);
          end

          [~, ~, z_mirror_symmetry] = shape.mirrorSymmetry();
          if z_mirror_symmetry
            ntheta = round(ntheta / 2);
          end
        end
      else
        ntheta = p.Results.size(1);
        nphi = p.Results.size(2);
      end

      % Special case for inifite axial symmetry
      [~, ~, z_axial_symmetry] = shape.axialSymmetry();
      if ~p.Results.full && z_axial_symmetry == 0
        nphi = 1;
      end

      % Calculate the angular grid
      [theta, phi] = ott.utils.angulargrid(ntheta, nphi);

      % Reduce the grid using z-symmetry and mirror symmetry
      if ~p.Results.full
        [~, ~, z_mirror_symmetry] = shape.mirrorSymmetry();
        if z_mirror_symmetry
          theta = theta / 2.0;    % [0, pi] -> [0, pi/2]
        end

        if z_axial_symmetry > 1
          phi = phi / z_axial_symmetry;  % [0, 2pi] -> [0, 2pi/p]
        end
      end

      if nargout == 2
        varargout{1} = theta;
        varargout{2} = phi;
      else
        % Calculate the radii
        r = shape.radii(theta, phi);
        if nargout == 1
          varargout{1} = [ r theta phi ];
        else
          varargout{1} = r;
          varargout{2} = theta;
          varargout{3} = phi;
        end
      end
    end
  end
  
  methods (Hidden)
    function b = insideRtpInternal(shape, rtp, varargin)
      % Determine if point is inside the shape (Spherical coordinates)

      % Determine if points are less than shape radii
      r = shape.radii(rtp(2, :), rtp(3, :));
      b = rtp(1, :).' < r;

    end

    function surfAddArgs(beam, p)
      % Add surface drawing args to the input parser for surf
      p.addParameter('points', []);
      p.addParameter('npoints', [100, 100]);
      surfAddArgs@ott.shapes.ShapeSph(beam, p);
    end
  end
end
