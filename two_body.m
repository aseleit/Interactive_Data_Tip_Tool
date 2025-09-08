%% UK vs Inverse-Dynamics Feedforward on a Dual-Stroke (Two-Mass) Stage
% - Output y = x2 (fine stage position)
% - Model: M*qdd + C*qd + K*q = u, q = [x1; x2]
% - Two approaches:
%   (1) ID (tracking-only): enforce x2dd = rdd -> minimal-norm u (collapses to u2-only here)
%   (2) UK (tracking + base quiet): enforce [x2dd = rdd; x1dd = 0] -> minimal kinetic-energy accel, then u = M*qdd + C*qd + K*q
clear; clc;

%% Parameters (representative)
m1 = 18.5;        % long-stroke moving mass [kg]  (cf. literature ~18-25 kg)
m2 = 17.0;        % short-stroke moving mass [kg] (cf. literature ~15-22 kg)
M  = diag([m1 m2]);

% Choose K so that the relative mode ~ 60 Hz (realistic for flexure-coupled stages)
f_rel = 60;                             % [Hz]
w_rel = 2*pi*f_rel;
k   = (w_rel^2) / (1/m1 + 1/m2);        % from two-mass relative mode
K   = k * [ 1 -1; -1  1 ];              % coupling only (simplified)
% Light damping (2% equiv. on relative mode):
m_eq = (m1*m2)/(m1+m2);
zeta = 0.02;
c    = 2*zeta*sqrt(k*m_eq);
C    = c * [ 1 -1; -1  1 ];

% Actuation maps (unit: force). Each actuator pushes its mass.
B = eye(2); % u = [u1; u2] acts directly on [x1; x2]

%% Reference trajectory: minimum-jerk (smooth to snap) step of Xf over T
Xf = 0.050;         % 50 mm move
T  = 0.30;          % 300 ms move time (step+settle window will extend)
Tsim = T + 0.20;    % simulate beyond move to see residuals
dt = 5e-4;          % 2 kHz "control" rate (feedforward update)
t  = 0:dt:Tsim;
[r, rd, rdd] = minjerk_traj(t, Xf, T);

%% Simulate both approaches (RK4 integration)
x0 = [0; 0]; v0 = [0; 0];

out_ID = runSim('ID', M,C,K,B, t, r, rd, rdd, x0, v0);
out_UK = runSim('UK', M,C,K,B, t, r, rd, rdd, x0, v0);

%% Metrics
metrics_ID = computeMetrics(out_ID, r, t);
metrics_UK = computeMetrics(out_UK, r, t);

disp('=== Metrics (RMSE over entire horizon; peaks are max abs) ===');
printMetrics('ID (tracking-only)', metrics_ID);
printMetrics('UK (track + base-quiet)', metrics_UK);

%% Plots
figure('Name','Tracking'); 
plot(t, r*1e3,'k--','LineWidth',1.5); hold on;
plot(t, out_ID.q(2,:)*1e3,'b','LineWidth',1.2);
plot(t, out_UK.q(2,:)*1e3,'r','LineWidth',1.2);
xlabel('Time [s]'); ylabel('x_2 / r  [mm]'); grid on;
legend('r','ID','UK'); title('Fine-stage position tracking');

figure('Name','Base acceleration & relative deflection');
subplot(2,1,1);
plot(t, out_ID.qdd(1,:), 'b'); hold on; plot(t, out_UK.qdd(1,:), 'r'); grid on;
ylabel('\ddot x_1 [m/s^2]'); legend('ID','UK'); title('Base (coarse) acceleration');
subplot(2,1,2);
plot(t, (out_ID.q(2,:)-out_ID.q(1,:))*1e6, 'b'); hold on;
plot(t, (out_UK.q(2,:)-out_UK.q(1,:))*1e6, 'r'); grid on;
xlabel('Time [s]'); ylabel('(x_2 - x_1) [\mum]'); legend('ID','UK'); title('Relative deflection');

figure('Name','Actuator forces');
plot(t, out_ID.u(1,:),'b--','LineWidth',1.0); hold on;
plot(t, out_ID.u(2,:),'b-','LineWidth',1.2);
plot(t, out_UK.u(1,:),'r--','LineWidth',1.0);
plot(t, out_UK.u(2,:),'r-','LineWidth',1.2);
grid on; xlabel('Time [s]'); ylabel('Force [N]');
legend('ID u_1','ID u_2','UK u_1','UK u_2'); title('Actuator forces');

%% ---- Functions ----
function out = runSim(method, M,C,K,B, t, r, rd, rdd, x0, v0)
    % Fixed-step RK4 to log q,qd,qdd,u
    dt = t(2)-t(1);
    q  = zeros(2, numel(t)); qd = q; qdd = q; u = q;
    q(:,1) = x0; qd(:,1) = v0;

    for k = 1:numel(t)
        tk = t(k);
        % Construct feedforward at current state
        switch method
            case 'ID'
                % Enforce x2dd = rdd via minimal-norm input (collapses to u1=0).
                u1 = 0;
                u2 = M(2,2)*rdd(k) + C(2,:)*qd(:,k) + K(2,:)*q(:,k);
                uk = [u1; u2];
                % Dynamics: qdd = M^{-1}(u - C*qd - K*q)
                qddk = M \ (uk - C*qd(:,k) - K*q(:,k));

            case 'UK'
                % Two constraints at acceleration level:
                %   A*qdd = b, with A = [0 1; 1 0], b = [rdd; 0]
                A = [0 1; 1 0];
                b = [rdd(k); 0];
                % Minimum kinetic-energy acceleration: qdd = M^{-1} A^T (A M^{-1} A^T)^{-1} b
                qddk = (M\A') * ((A/M*A') \ b);
                % Exact feedforward to realize that acceleration
                uk = M*qddk + C*qd(:,k) + K*q(:,k);

            otherwise
                error('Unknown method');
        end
        u(:,k)   = uk;
        qdd(:,k) = qddk;

        % Integrate to next step with RK4 (except at last index)
        if k < numel(t)
            qk  = q(:,k);   qdk = qd(:,k);
            f = @(qq, vv, tt, uu) [vv;  M \ (uu - C*vv - K*qq)];
            % Build u(t) as piecewise-constant over [t_k, t_{k+1})
            k1 = f(qk,            qdk,            tk,            uk);
            k2 = f(qk+0.5*dt*k1(1:2), qdk+0.5*dt*k1(3:4), tk+0.5*dt, uk);
            k3 = f(qk+0.5*dt*k2(1:2), qdk+0.5*dt*k2(3:4), tk+0.5*dt, uk);
            k4 = f(qk+    dt*k3(1:2), qdk+    dt*k3(3:4), tk+    dt, uk);
            inc = (k1 + 2*k2 + 2*k3 + k4)/6;
            q(:,k+1)  = qk  + dt*inc(1:2);
            qd(:,k+1) = qdk + dt*inc(3:4);
        end
    end
    out.t = t; out.q = q; out.qd = qd; out.qdd = qdd; out.u = u;
end

function [r, rd, rdd] = minjerk_traj(t, Xf, T)
    % r(t) = Xf*(10 s^3 - 15 s^4 + 6 s^5), s = min(max(t/T,0),1)
    s = min(max(t./T,0),1);
    r   = Xf*(10*s.^3 - 15*s.^4 + 6*s.^5);
    rd  = Xf*(30*s.^2 - 60*s.^3 + 30*s.^4).*(1/T);
    rdd = Xf*(60*s    - 180*s.^2 + 120*s.^3).*(1/T^2);
end

function Mx = computeMetrics(out, r, t)
    dt = t(2)-t(1);
    e  = out.q(2,:) - r;                % tracking error
    Mx.trk_rmse   = sqrt(mean(e.^2));
    Mx.trk_peak   = max(abs(e));
    Mx.base_acc_rms = sqrt(mean(out.qdd(1,:).^2));
    Mx.base_acc_pk  = max(abs(out.qdd(1,:)));
    rel = out.q(2,:) - out.q(1,:);
    Mx.rel_defl_pk_um = 1e6*max(abs(rel));
    Mx.u_rms     = sqrt(mean(sum(out.u.^2,1)));
    Mx.u_peak    = max(vecnorm(out.u,2,1));
    Mx.energy    = sum(sum(out.u.^2,1))*dt; % \int (u1^2+u2^2) dt
end

function printMetrics(label, Mx)
    fprintf('\n%s\n', label);
    fprintf('  Track RMSE       : %.3e m\n',   Mx.trk_rmse);
    fprintf('  Track Peak       : %.3e m\n',   Mx.trk_peak);
    fprintf('  Base acc RMS     : %.3f m/s^2\n', Mx.base_acc_rms);
    fprintf('  Base acc Peak    : %.3f m/s^2\n', Mx.base_acc_pk);
    fprintf('  Rel defl Peak    : %.2f um\n',   Mx.rel_defl_pk_um);
    fprintf('  Force RMS (||u||): %.2f N\n',    Mx.u_rms);
    fprintf('  Force Peak       : %.2f N\n',    Mx.u_peak);
    fprintf('  Energy \u222B u^2 dt : %.2f N^2 s\n', Mx.energy);
end
