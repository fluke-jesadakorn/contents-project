import React, { useState } from 'react';
import { canAccessTab, type TabName } from '@/lib/permissions';

interface NavbarProps {
  users: any[];
  currentUser: any;
  onUserChange: (userId: string) => void;
  activeTab: 'workbench' | 'ledger' | 'cockpit';
  setActiveTab: (tab: 'workbench' | 'ledger' | 'cockpit') => void;
  journalsCount: number;
}

export const Navbar: React.FC<NavbarProps> = ({
  users,
  currentUser,
  onUserChange,
  activeTab,
  setActiveTab,
  journalsCount
}) => {
  const [dropdownOpen, setDropdownOpen] = useState(false);

  const getAvatar = (role?: string) => {
    switch (role) {
      case 'staff': return '👨‍💻';
      case 'accountant': return '👩‍🔬';
      case 'manager': return '👩‍💼';
      case 'admin': return '👑';
      default: return '👤';
    }
  };

  const getRoleBadgeColor = (role?: string) => {
    switch (role) {
      case 'staff': return 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30';
      case 'accountant': return 'bg-indigo-500/10 text-indigo-400 border-indigo-500/30';
      case 'manager': return 'bg-amber-500/10 text-amber-400 border-amber-500/30';
      case 'admin': return 'bg-purple-500/10 text-purple-400 border-purple-500/30';
      default: return 'bg-slate-500/10 text-slate-400 border-slate-500/30';
    }
  };

  const getRoleDisplayName = (role?: string) => {
    switch (role) {
      case 'staff': return 'พนักงานผู้เบิก (Staff)';
      case 'accountant': return 'ผู้ตรวจสอบบัญชี (Accountant)';
      case 'manager': return 'ผู้จัดการผู้อนุมัติ (Manager)';
      case 'admin': return 'ผู้บริหารระดับสูง (Executive)';
      default: return role || 'Unknown';
    }
  };

  return (
    <header className="relative z-50 flex flex-col lg:flex-row justify-between items-stretch lg:items-center p-4 lg:px-8 mb-8 bg-slate-950/80 backdrop-blur-xl border-b border-slate-800/80 gap-4 sticky top-0 shadow-2xl shadow-black/50">
      {/* LEFT: BRANDING & LOGO */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3.5">
          <div className="p-3 bg-gradient-to-tr from-indigo-600 via-purple-600 to-pink-600 rounded-2xl text-white shadow-lg shadow-indigo-500/25 text-xl flex items-center justify-center animate-pulse">
            📊
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-2xl font-black tracking-tight bg-gradient-to-r from-white via-slate-100 to-indigo-300 bg-clip-text text-transparent">
                FinAgent ERP
              </h1>
              <span className="text-[10px] px-2 py-0.5 rounded-full bg-indigo-500/20 text-indigo-300 font-mono font-bold border border-indigo-500/30">
                v2.5 AI GA
              </span>
            </div>
            <p className="text-[11px] text-slate-400 mt-0.5 font-sans">
              Autonomous OCR Ingestion, Double-Entry GL & GAAP/TFRS Financial Engine
            </p>
          </div>
        </div>

        {/* Mobile menu toggle button if needed */}
      </div>

      {/* CENTER: NAVIGATION TABS */}
      <div className="flex bg-slate-900/80 p-1 rounded-2xl border border-slate-800/80 shadow-inner">
        {([
          { key: 'workbench' as TabName, icon: '🏢', label: 'Role Workbench' },
          { key: 'ledger' as TabName, icon: '📒', label: `General Ledger (${journalsCount})` },
          { key: 'cockpit' as TabName, icon: '👑', label: 'C-Level Cockpit' },
        ]).map((tab) => {
          const hasAccess = canAccessTab(currentUser?.role_name, tab.key);
          const isActive = activeTab === tab.key;

          return (
            <button
              key={tab.key}
              onClick={() => hasAccess && setActiveTab(tab.key)}
              disabled={!hasAccess}
              title={!hasAccess ? `สิทธิ์ไม่เพียงพอ — บทบาท ${currentUser?.role_name || 'unknown'} ไม่สามารถเข้าถึงได้` : undefined}
              className={`flex-1 lg:flex-initial px-4 py-2 text-xs font-bold rounded-xl transition-all flex items-center justify-center gap-2 ${
                !hasAccess
                  ? 'text-slate-600 cursor-not-allowed opacity-50'
                  : isActive
                    ? 'bg-gradient-to-r from-indigo-600 to-purple-600 text-white shadow-lg shadow-indigo-500/25 scale-[1.02]'
                    : 'text-slate-400 hover:text-white hover:bg-slate-800/50 cursor-pointer'
              }`}
            >
              <span>{hasAccess ? tab.icon : '🔒'}</span>
              <span>{tab.label}</span>
            </button>
          );
        })}
      </div>

      {/* RIGHT: USER SIMULATION HUB (MOVED TO TOP RIGHT) */}
      <div className="flex items-center justify-end gap-3">
        <div className="hidden sm:flex flex-col items-end mr-1">
          <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider font-mono">Active Simulation Mode</span>
          <span className="text-xs font-semibold text-slate-200">
            {currentUser ? getRoleDisplayName(currentUser.role_name) : 'Select Persona'}
          </span>
        </div>

        {/* DROPDOWN SELECTOR */}
        <div className="relative">
          <button
            onClick={() => setDropdownOpen(!dropdownOpen)}
            className={`flex items-center gap-2.5 px-3.5 py-2 rounded-2xl border transition-all cursor-pointer shadow-xl ${
              dropdownOpen
                ? 'bg-slate-900 border-indigo-500 ring-2 ring-indigo-500/20'
                : 'bg-slate-900/60 hover:bg-slate-900 border-slate-800 hover:border-slate-700'
            }`}
          >
            <span className="text-xl leading-none">{getAvatar(currentUser?.role_name)}</span>
            <div className="text-left hidden md:block">
              <span className="block text-xs font-bold text-white leading-tight">
                {currentUser?.fullname?.split(' ')[0] || 'User'}
              </span>
              <span className={`inline-block px-1.5 py-0.2 rounded text-[8px] font-mono font-bold uppercase mt-0.5 border ${getRoleBadgeColor(currentUser?.role_name)}`}>
                {currentUser?.role_name === 'admin' ? 'EXECUTIVE' : currentUser?.role_name}
              </span>
            </div>
            <span className="text-slate-400 text-xs ml-1 transition-transform duration-200" style={{ transform: dropdownOpen ? 'rotate(180deg)' : 'rotate(0deg)' }}>
              ▼
            </span>
          </button>

          {/* DROPDOWN MENU */}
          {dropdownOpen && (
            <>
              {/* BACKDROP TO CLOSE DROPDOWN */}
              <div 
                className="fixed inset-0 z-40" 
                onClick={() => setDropdownOpen(false)}
              />
              
              <div className="absolute right-0 mt-2 w-72 bg-slate-950 border border-slate-800 rounded-2xl shadow-2xl shadow-black p-2 z-50 animate-fade-in divide-y divide-slate-900">
                <div className="px-3 py-2 text-[10px] font-mono font-bold uppercase tracking-wider text-slate-400">
                  ⚡ Switch User Role Persona
                </div>
                <div className="py-1 space-y-1 max-h-80 overflow-y-auto">
                  {users.map((u) => {
                    const isSelected = currentUser?.id === u.id;
                    return (
                      <button
                        key={u.id}
                        onClick={() => {
                          onUserChange(u.id.toString());
                          setDropdownOpen(false);
                        }}
                        className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-left transition-all ${
                          isSelected
                            ? 'bg-indigo-600/20 border border-indigo-500/40 text-white'
                            : 'hover:bg-slate-900 text-slate-300 hover:text-white'
                        }`}
                      >
                        <span className="text-xl">{getAvatar(u.role_name)}</span>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center justify-between">
                            <span className="text-xs font-bold truncate">{u.fullname}</span>
                            {isSelected && <span className="text-indigo-400 text-xs font-bold">✓</span>}
                          </div>
                          <div className="flex items-center gap-1.5 mt-0.5">
                            <span className="text-[9px] text-slate-500 font-mono">{u.employee_code}</span>
                            <span className="text-slate-700">•</span>
                            <span className="text-[9px] text-slate-400 uppercase font-mono">{u.role_name === 'admin' ? 'CFO/CEO' : u.role_name}</span>
                          </div>
                        </div>
                      </button>
                    );
                  })}
                </div>
              </div>
            </>
          )}
        </div>
      </div>
    </header>
  );
};
