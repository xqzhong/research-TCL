%单天优化
clc; clear;
global dt T T_tcl I1 I I2 EV TCL
EV = 60;%EV总数，额定功率为3.7kW
TCL = 100;%空调总数
T = 15 / 60;%控制周期15min
dt = 1 / 60 / 60;%空调控制周期2s
I1 = 24 / dt;
I = 24 / T;
T_tcl = 1; %空调控制指令周期60min
I_tcl = T_tcl / T;
T_mpc = 6;
I2 = 24 / T_tcl;
LOAD = 180;%LOAD最大负荷（kW）
WIND = 200;%WIND风电装机容量（kW）
tielineSold = 40;
tielineBuy = 300;
nod33 = 33;
tolerance = 0.01;
mkt_init;   %市场初始化
price_init;
tielineRecord = zeros(1,I);%自联络线购电量
gridPriceRecord4 = zeros(1,I);
priceRecord = zeros(1,I);
hasCongest = 0;
offset = 0;
isMpc = 1;
EV_init;
EVpowerRecord = zeros(EV, I);
EVavgPowerRecord = zeros(1, EV);
EVmaxPowerRecord = zeros(1, EV);
EVminPowerRecord = zeros(1, EV);
EVdata_E = zeros(EV, I);
EVdata_E(:, mod(offset / T , I) + 1) = unifrnd(0.1, 0.5, EV, 1) .* EVdata_capacity';
EV_totalpowerRecord = zeros(1, I);%EV总充电功率

TCL_init;
TCLpowerRecord = zeros(TCL, I2);
TCLsetPowerRecord = zeros(1, TCL);
TCLmaxPowerRecord = zeros(1, TCL);
TCLminPowerRecord = zeros(1, TCL);
TCLdata_Ta(:, mod(offset / dt , I1) + 1) =  unifrnd(25.8, 26.2, TCL, 1); 
TCL_totalpowerRecord = zeros(1, I2);
SOArecord = zeros(TCL, I2);

% Tout = [Tout(721:1440); Tout(1:720)];
% Tout = 32 * ones(1440, 1);
for t_index = 1: I
    gridPrice = gridPriceRecord(floor((t_index - 1) * T) + 1);
    gridPriceRecord4(t_index) = gridPrice;
end
for i = 1: I
    t_index = mod(i - 1 + offset / T , I) + 1;
    mod_t = mod(t_index, I) + 1;
    mod_t_1 = mod(t_index - 1, I) + 1; 
    time = (t_index - 1) * T ;
    gridPrice = gridPriceRecord4(t_index);
    wp = windPowerRecord(t_index);
    lp = loadPowerRecord(t_index);
    totalPowerEV = 0;
    bidCurve = zeros(1, step + 1);
    %联络线投标
    tielineCurve = zeros(1, step + 1);
    sigma = sigmaRecord(floor(time) + 1);
    for q = 1 : step + 1
        if pCurve(q) < gridPrice
            tielineCurve(q) = tielineSold;
        elseif pCurve(q) >= gridPrice
            tielineCurve(q) = -tielineBuy;
        end
    end
    if t_index > 3
        if  hasCongest == 0 && priceRecord(t_index-1) > mkt_max - 0.1 && priceRecord(t_index - 2) > mkt_max - 0.1
            hasCongest = 1;
        elseif hasCongest == 1 && priceRecord(t_index - 1) / gridPriceRecord4(t_index - 1) < 1.15 ...
            && priceRecord(t_index - 1) / gridPriceRecord4(t_index - 1) < 1.15...
                && gridPriceRecord4(t_index - 1) < mkt_max - 0.4 && gridPriceRecord4(t_index - 2) < mkt_max - 0.4
            hasCongest = 0;
        end
    end
    for ev = 1 : EV
        if time >= EVdata(1, ev) || time < EVdata(2,ev)
            %预测未来电价
            k1 = 1;
            if time >= EVdata(1, ev)
                prePrice = [ gridPriceRecord4(t_index : I ) , gridPriceRecord4(1 : floor( EVdata(2,ev) / T)) ];
            else
                prePrice = gridPriceRecord4(t_index : floor( EVdata(2,ev) / T));
            end
            [Pmax, Pmin, ~] = EVBidPara(T, EVdata_E(ev, t_index), EVdata_alpha(ev),  EVdata(2,ev) + 24 - time, ...
                EVdata_mile(ev), EVdata_capacity(ev), PN);
            %底层优化算法
            if hasCongest == 1
                delta_E = max(0, 0.8 * EVdata_capacity(ev) + (1-0.8) * EVdata_mile(ev) - EVdata_E(ev, t_index));
            else
                delta_E = max(0, EVdata_alpha(ev) * EVdata_capacity(ev) + (1 - EVdata_alpha(ev)) * EVdata_mile(ev) ...
                    - EVdata_E(ev, t_index));
            end
            if delta_E==0
                Pavg=0;
            else
                [meanpre_price_order, tmp1]= sort(prePrice);
                tmp2 = ceil(delta_E / T / PN);
                if tmp2 >= length(meanpre_price_order)
                    Pavg = min(PN, delta_E / T / tmp2);
                else
                    min_bidprice = meanpre_price_order(tmp2);
                    if tmp2 + 1 <= length(meanpre_price_order)
                        tmp3 = meanpre_price_order(tmp2 + 1);
                        while tmp3 - min_bidprice < tolerance
                            tmp2 = tmp2 + 1;
                            if tmp2 + 1 > length(meanpre_price_order)
                                break;
                            else
                                tmp3 = meanpre_price_order(tmp2 + 1);
                            end
                        end
                    end
                    [tmp4, tmp5] = find(tmp1 == 1);
                    if tmp5 <= tmp2
                        Pavg = delta_E / T / tmp2;
                    else
                        Pavg = 0;
                    end
                end
                clear tmp1 tmp2 tmp3 tmp4 tmp5
            end
            Pavg = max(Pmin,Pavg);
            Pavg = min(Pmax,Pavg);
            EVmaxPowerRecord(1, ev) = Pmax;
            EVavgPowerRecord(1, ev) = Pavg;
            EVminPowerRecord(1, ev) = Pmin;
            if hasCongest == 1
                bidCurve = bidCurve + EVbid(mkt, Pmax, Pmin, Pavg, 3, gridPrice, sigma);
            else
                bidCurve = bidCurve + EVbid(mkt, Pmax, Pmin, Pavg, EVdata_beta(ev), gridPrice, sigma);
            end
        end
    end
    if mod(t_index, I_tcl) == 1
        N = T_mpc / T_tcl;
        t_index_tcl = floor(t_index / I_tcl) + 1;
        totalPowerTCL = 0;
        TCLmpcPriceRecord = zeros(N, 1);
        ToutRecord = zeros(N, 1);
        for n = 1 : N
            TCLmpcPriceRecord(n) = gridPriceRecord(floor(mod(time + T_tcl * (n - 1), 24)) + 1);
            minute_s = mod(time * 60 + T_tcl * (n - 1) * 60 + 1, 1440);
            minute_e = time * 60 + T_tcl * n * 60;
            if minute_e > 1440
                minute_e = minute_e - 1440;
            end
            if minute_e < minute_s
                x = 1;
            end
            ToutRecord(n) = mean(Tout(minute_s :minute_e));
        end
        for tcl = 1 : TCL
            %按跟踪目标温度投标
            if isMpc == 0
                [Pmax, Pmin, Pset] = ACload(TCLdata_T(1, tcl), TCLdata_T(2, tcl),  TCLdata_Ta(tcl, time / dt + 1 ),...
                    TCLdata_R(1, tcl), TCLdata_C(1, tcl), Tout(time * 60 + 1), TCLdata_PN(1, tcl));
            else %按底层mpc投标
                [Pmax, Pmin, Pset, SOA] = TCLBidPara(TCLmpcPriceRecord, TCLdata_Ta(tcl, time / dt + 1), ToutRecord, ...
                    TCLdata_T(1, tcl), TCLdata_T(2, tcl), TCLdata_R(1, tcl), TCLdata_C(1, tcl), TCLdata_PN(1, tcl), TCLdata_beta(1, tcl));
            end
            SOArecord(tcl, t_index_tcl) = SOA;
            TCLmaxPowerRecord(1, tcl) = Pmax;
            TCLsetPowerRecord(1, tcl) = Pset;
            TCLminPowerRecord(1, tcl) = Pmin;
            if hasCongest == 1
                bidCurve = bidCurve + EVbid(mkt, Pmax, Pmin, Pset, 3, gridPrice, sigma);
            else
                bidCurve = bidCurve + EVbid(mkt, Pmax, Pmin, Pset, TCLdata_beta(tcl), gridPrice, sigma);
            end
        end
    end
    %出清
    clcPrice = calculateIntersection(mkt, 0, bidCurve - wp + lp + tielineCurve + totalPowerTCL);
    priceRecord(t_index) = clcPrice;
    %反聚合
    %EV
    for ev = 1 : EV
        if time >= EVdata(1,ev) || time < EVdata(2, ev)
            if hasCongest == 1
                bidCurve = EVbid(mkt, EVmaxPowerRecord(1, ev), EVminPowerRecord(1, ev), EVavgPowerRecord(1, ev),...
                    3, gridPrice, sigma);
            else
                bidCurve = EVbid(mkt, EVmaxPowerRecord(1, ev), EVminPowerRecord(1, ev), EVavgPowerRecord(1, ev),...
                    EVdata_beta(ev), gridPrice, sigma);
            end
            power_EV = handlePriceUpdate(bidCurve, clcPrice, mkt );
            EVpowerRecord(ev, t_index) = power_EV;
            totalPowerEV = totalPowerEV + power_EV;
            EVdata_E(ev, mod_t) = EVdata_E(ev, mod_t_1) + power_EV * T;
        elseif time > EVdata(2, ev)
            EVdata_E(ev, mod_t) = EVdata_E(ev, mod_t_1);
        end
    end
    EV_totalpowerRecord(t_index) = totalPowerEV;

    %TCL
    if mod(t_index, I_tcl) == 1
        for tcl = 1 : TCL
            if hasCongest == 1
                bidCurve = EVbid(mkt, TCLmaxPowerRecord(1, tcl), TCLminPowerRecord(1, tcl), TCLsetPowerRecord(1, tcl),...
                    3, gridPrice, sigma);
            else
                bidCurve = EVbid(mkt, TCLmaxPowerRecord(1, tcl), TCLminPowerRecord(1, tcl), TCLsetPowerRecord(1, tcl),...
                    TCLdata_beta(tcl), gridPrice, sigma);
            end
            power_TCL = handlePriceUpdate(bidCurve, clcPrice, mkt );
            TCLpowerRecord(tcl, t_index_tcl) = power_TCL;
            totalPowerTCL = totalPowerTCL + power_TCL;
        end
        TCLupdate();
        TCL_totalpowerRecord(t_index_tcl) = totalPowerTCL;
    end
    tmp = totalPowerEV + totalPowerTCL;
    tielineRecord(t_index) = tmp - wp + lp;%正表示自主网购电，负表示向主网售电
end
for tcl = 1 : TCL
    TCLdata_Ta(tcl,:) = (TCLdata_Ta(tcl,:) - TCLdata_T(2, tcl)) / (TCLdata_T(1, tcl) - TCLdata_T(2, tcl));
end
tongji;