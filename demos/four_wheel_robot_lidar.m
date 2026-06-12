% four_wheel_robot_lidar.m
% 4-wheel robot with a lidar-style range sensor and obstacle avoidance.
% - Circular obstacles, ray-cast lidar (25 beams, 2 m range), drawn live
% - Gap-seeking avoidance: robot steers toward the lidar beam that best
%   combines clearance with progress toward the next waypoint
% Pure MATLAB - no toolboxes required.
%
% Created by Claude via the MATLAB MCP server.

%% Parameters
bodyLen  = 0.50;  bodyWid = 0.35;
wheelLen = 0.16;  wheelWid = 0.06;
robotRad = 0.30;            % inflation radius for clearance (m)
dt       = 0.05;
vMax     = 0.8;
kHeading = 2.8;
wpRadius = 0.30;
maxSteps = 6000;

% Lidar
nBeams   = 25;
fov      = deg2rad(240);                       % field of view
beamAng  = linspace(-fov/2, fov/2, nBeams);    % robot-relative angles
lidarMax = 2.0;                                % max range (m)

% Course and obstacles [x y radius]
waypoints = [0 0; 3 0; 4 2; 2 4; -1 3; -1.5 1; 0 0];
obstacles = [1.5 -0.35 0.45;
             3.6  1.00 0.40;
             2.9  3.20 0.50;
             0.3  3.30 0.45;
            -1.45 2.00 0.40];

%% Figure setup
fig = figure('Name', '4-Wheel Robot + Lidar', 'NumberTitle', 'off');
ax = axes(fig); hold(ax, 'on'); grid(ax, 'on'); axis(ax, 'equal');
pad = 1.5;
xlim(ax, [min(waypoints(:,1))-pad, max(waypoints(:,1))+pad]);
ylim(ax, [min(waypoints(:,2))-pad, max(waypoints(:,2))+pad]);
xlabel(ax, 'X (m)'); ylabel(ax, 'Y (m)');
title(ax, '4-Wheel Robot: Lidar + Obstacle Avoidance');

plot(ax, waypoints(:,1), waypoints(:,2), 'k--o', 'MarkerFaceColor', 'y', ...
    'DisplayName', 'Waypoint course');
th = linspace(0, 2*pi, 40);
for k = 1:size(obstacles, 1)
    patch(ax, obstacles(k,1) + obstacles(k,3)*cos(th), ...
              obstacles(k,2) + obstacles(k,3)*sin(th), ...
              [0.85 0.4 0.35], 'EdgeColor', [0.5 0.2 0.15], ...
              'FaceAlpha', 0.8, 'HandleVisibility', 'off');
end
trail = animatedline(ax, 'Color', [0 0.45 0.74], 'LineWidth', 1.5, ...
    'DisplayName', 'Robot path');
beamLines = plot(ax, NaN, NaN, '-', 'Color', [0.2 0.75 0.3 0.35], ...
    'DisplayName', 'Lidar beams');
hitPts = plot(ax, NaN, NaN, 'r.', 'MarkerSize', 10, ...
    'DisplayName', 'Lidar hits');
legend(ax, 'Location', 'best');

% Robot body graphics
tf = hgtransform('Parent', ax);
patch('Parent', tf, 'XData', [-1 1 1 -1]*bodyLen/2, ...
    'YData', [-1 -1 1 1]*bodyWid/2, 'FaceColor', [0.3 0.6 0.9], ...
    'EdgeColor', 'k', 'HandleVisibility', 'off');
patch('Parent', tf, 'XData', [bodyLen/2-0.1 bodyLen/2 bodyLen/2-0.1], ...
    'YData', [-0.07 0 0.07], 'FaceColor', 'r', 'EdgeColor', 'none', ...
    'HandleVisibility', 'off');
wx = [-1 -1 1 1] * bodyLen*0.30;
wy = [-1 1 -1 1] * (bodyWid/2 + wheelWid/2);
for k = 1:4
    patch('Parent', tf, 'XData', wx(k)+[-1 1 1 -1]*wheelLen/2, ...
        'YData', wy(k)+[-1 -1 1 1]*wheelWid/2, ...
        'FaceColor', [0.15 0.15 0.15], 'EdgeColor', 'none', ...
        'HandleVisibility', 'off');
end

%% Simulation loop
pose = [waypoints(1,1); waypoints(1,2); 0];
wpIdx = 2;
distTotal = 0; simTime = 0;
minClearance = inf;
collided = false;

for step = 1:maxSteps
    target = waypoints(wpIdx, :)';
    delta = target - pose(1:2);
    if norm(delta) < wpRadius
        wpIdx = wpIdx + 1;
        if wpIdx > size(waypoints, 1), break; end
        continue;
    end

    % ---- Lidar scan: ray-cast every beam against all circles ----
    ranges = lidarMax * ones(1, nBeams);
    for b = 1:nBeams
        a = pose(3) + beamAng(b);
        u = [cos(a); sin(a)];
        for k = 1:size(obstacles, 1)
            cp = obstacles(k, 1:2)' - pose(1:2);
            bb = u' * cp;
            disc = bb^2 - (cp'*cp - obstacles(k,3)^2);
            if disc >= 0
                t = bb - sqrt(disc);
                if t > 0 && t < ranges(b)
                    ranges(b) = t;
                end
            end
        end
    end

    % ---- Collision / clearance bookkeeping ----
    clearNow = inf;
    for k = 1:size(obstacles, 1)
        clearNow = min(clearNow, ...
            norm(obstacles(k,1:2)' - pose(1:2)) - obstacles(k,3));
    end
    minClearance = min(minClearance, clearNow);
    if clearNow < robotRad * 0.6
        collided = true;
        break;
    end

    % ---- Gap-seeking steering ----
    desiredTh = atan2(delta(2), delta(1));
    goalRel = atan2(sin(desiredTh - pose(3)), cos(desiredTh - pose(3)));
    clearance = max(ranges - 1.5*robotRad, 0);
    % Erode clearance over neighboring beams so the robot's width is
    % respected: a beam is only as good as its local neighborhood.
    clearEro = clearance;
    for b = 1:nBeams
        lo = max(1, b-3); hi = min(nBeams, b+3);
        clearEro(b) = min(clearance(lo:hi));
    end
    score = min(clearEro, 1.2) - 0.45 * abs(beamAng - goalRel);
    [~, best] = max(score);
    steerErr = beamAng(best);

    % Emergency reflex: if anything is dangerously close, turn hard away
    [closest, cIdx] = min(ranges - robotRad);
    if closest < 0.35
        away = -sign(beamAng(cIdx) + 1e-3);
        steerErr = away * deg2rad(70);
    end

    omega = kHeading * steerErr;
    aheadIdx = abs(beamAng) < deg2rad(35);
    minAhead = min(clearEro(aheadIdx));
    v = vMax * max(0.12, min(1, minAhead / 1.2)) * max(0.15, cos(steerErr));

    % ---- Kinematics update ----
    pose(1) = pose(1) + v * cos(pose(3)) * dt;
    pose(2) = pose(2) + v * sin(pose(3)) * dt;
    pose(3) = pose(3) + omega * dt;
    distTotal = distTotal + v * dt;
    simTime = simTime + dt;

    % ---- Animate robot, beams, and hit points ----
    set(tf, 'Matrix', makehgtform('translate', [pose(1) pose(2) 0], ...
        'zrotate', pose(3)));
    addpoints(trail, pose(1), pose(2));
    bx = nan(1, 3*nBeams); by = bx;
    hx = []; hy = [];
    for b = 1:nBeams
        a = pose(3) + beamAng(b);
        ex = pose(1) + ranges(b)*cos(a);
        ey = pose(2) + ranges(b)*sin(a);
        bx(3*b-2:3*b) = [pose(1) ex NaN];
        by(3*b-2:3*b) = [pose(2) ey NaN];
        if ranges(b) < lidarMax - 1e-6
            hx(end+1) = ex; %#ok<SAGROW>
            hy(end+1) = ey; %#ok<SAGROW>
        end
    end
    set(beamLines, 'XData', bx, 'YData', by);
    set(hitPts, 'XData', hx, 'YData', hy);
    drawnow limitrate;
end

drawnow;
if collided
    fprintf('COLLISION after %.1f s at (%.2f, %.2f). Min clearance %.2f m.\n', ...
        simTime, pose(1), pose(2), minClearance);
elseif wpIdx > size(waypoints, 1)
    fprintf('Course complete: %.1f m in %.1f s. Min obstacle clearance: %.2f m.\n', ...
        distTotal, simTime, minClearance);
else
    fprintf('Stopped at step limit (possibly stuck). Min clearance: %.2f m.\n', ...
        minClearance);
end
