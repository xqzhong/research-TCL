xlim([0, 24 * DAY]);
xticks(0 : 12 : 24 * DAY);
% xticklabels({ '0', '12:00', '1', '12:00', '2', '12:00', '3', '12:00', '4', '12:00', '5', '12:00', '6', '12:00', '7'});
% set(gca,'xticklabel','');
xticklabels({ '0', '', '1', '', '2', '', '3', '', '4', '', '5', '', '6', '', '7'});
xlabel('t(day)')
set(gcf,'unit','normalized','position',[0,0,0.3,0.16]);