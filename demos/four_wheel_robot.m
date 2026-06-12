% four_wheel_robot.m
% Basic 4-wheel (skid-steer / differential drive) robot simulation.
% The robot follows a series of waypoints using a proportional
% heading controller. Pure MATLAB - no toolboxes required.
%
% Created by Claude via the MATLAB MCP server.

%% Parameters
bodyLen   = 0.50;          % robot body length (m)
bodyWid   = 0.35;          % robot body width (m)
wheelLen  = 0.16;          % wheel length (m)
wheelWid  = 0.06;          % wheel width (m)
dt        = 0.05;          % time step (s)
vMax      = 0.8;           % max forward speed (m/s)
kHeading  = 2.5;           % heading P-controller gain
wpRadius  = 0.25;          % waypoint reached threshold (m)
maxSteps  = 5000;          % safety limit

% Waypoint course (m)
waypoints = [0 0; 3 0; 4 2; 2 4; -1 3; -1.5 1; 0 0];

%% Figure setup
fig = figure('Name', '4-Wheel Robot Simulation', 'NumberTitle', 'off');
ax = axes(fig); hold(ax, 'on'); grid(ax, 'on'); axis(ax, 'equal');
pad = 1.2;
xlim(ax, [min(waypoints(:,1))-pad, max(waypoints(:,1))+pad]);
ylim(ax, [min(waypoints(:,2))-pad, max(waypoints(:,2))+pad]);
xlabel(ax, 'X (m)'); ylabel(ax, 'Y (m)');
title(ax, '4-Wheel Robot: Waypoint Following');

plot(ax, waypoints(:,1), waypoints(:,2), 'k--o', 'MarkerFaceColor', 'y', ...
    'DisplayName', 'Waypoint course');
trail = animatedline(ax, 'Color', [0 0.45 0.74], 'LineWidth', 1.5, ...
    'DisplayName', 'Robot path');
legend(ax, 'Location', 'best');

% Robot graphics: body + 4 wheels inside one transform
tf = hgtransform('Parent', ax);
bodyX = [-1 1 1 -1] * bodyLen/2;
bodyY = [-1 -1 1 1] * bodyWid/2;
patch('Parent', tf, 'XData', bodyX, 'YData', bodyY, ...
    'FaceColor', [0.3 0.6 0.9], 'EdgeColor', 'k', 'HandleVisibility', 'off');
% heading marker (nose triangle)
patch('Parent', tf, 'XData', [bodyLen/2-0.1 bodyLen/2 bodyLen/2-0.1], ...
    'YData', [-0.07 0 0.07], 'FaceColor', 'r', 'EdgeColor', 'none', ...
    'HandleVisibility', 'off');
% 4 wheels at the corners
wx = [-1 -1 1 1] * bodyLen*0.30;
wy = [-1 1 -1 1] * (bodyWid/2 + wheelWid/2);
for k = 1:4
    patch('Parent', tf, ...
        'XData', wx(k) + [-1 1 1 -1]*wheelLen/2, ...
        'YData', wy(k) + [-1 -1 1 1]*wheelWid/2, ...
        'FaceColor', [0.15 0.15 0.15], 'EdgeColor', 'none', ...
        'HandleVisibility', 'off');
end

%% Simulation loop
pose = [waypoints(1,1); waypoints(1,2); 0];   % [x; y; theta]
wpIdx = 2;
distTotal = 0;
simTime = 0;

for step = 1:maxSteps
    target = waypoints(wpIdx, :)';
    delta = target - pose(1:2);
    distToWp = norm(delta);

    if distToWp < wpRadius
        wpIdx = wpIdx + 1;
        if wpIdx > size(waypoints, 1)
            break;  % course complete
        end
        continue;
    end

    % Heading controller
    desiredTh = atan2(delta(2), delta(1));
    headErr = atan2(sin(desiredTh - pose(3)), cos(desiredTh - pose(3)));
    omega = kHeading * headErr;
    v = vMax * max(0.15, cos(headErr));   % slow down for sharp turns

    % Differential-drive kinematics
    pose(1) = pose(1) + v * cos(pose(3)) * dt;
    pose(2) = pose(2) + v * sin(pose(3)) * dt;
    pose(3) = pose(3) + omega * dt;

    distTotal = distTotal + v * dt;
    simTime = simTime + dt;

    % Animate
    set(tf, 'Matrix', makehgtform('translate', [pose(1) pose(2) 0], ...
        'zrotate', pose(3)));
    addpoints(trail, pose(1), pose(2));
    drawnow limitrate;
end

drawnow;
fprintf('Course complete: %d waypoints, %.1f m traveled in %.1f s sim time.\n', ...
    size(waypoints, 1), distTotal, simTime);
