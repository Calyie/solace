// Crisis numbers stored on the device. Checked against official sources on 2026-10-29 (3114.fr; crtc.gc.ca and
// 988.ca; befrienders.org.my; Thailand's Department of Mental Health and Samaritans of Thailand) and on 2026-11-05
// for Ireland (hse.ie, pieta.ie, Text About It), the United Kingdom (NHS 111 option 2, Samaritans, Shout) and Nigeria
// (Lifeline International's SURPIN listing; Nigerian lines disagree between sources, so only the most consistent are
// kept), and on 2026-11-14 for the United States (samhsa.gov/mental-health/988, crisistextline.org) and the lines for
// young people (kidshelpphone.ca, ispcc.ie and childline.ie, childline.org.uk, filsantejeunes.com). Numbers change:
// re-check before every release.

class CrisisLine {
  const CrisisLine(this.name, this.number, this.detail);
  final String name;
  final String number;
  final String detail;
}

class CountryCrisis {
  const CountryCrisis(this.country, this.lines, this.emergency);
  final String country;
  final List<CrisisLine> lines;
  final List<CrisisLine> emergency;
}

const crisisChecked = '14 November 2026';

const crisisByCountry = <String, CountryCrisis>{
  'Ireland': CountryCrisis('Ireland', [
    CrisisLine('Pieta crisis helpline', '1800 247 247', 'Free, 24 hours, for suicidal thoughts and self-harm. Or text HELP to 51444.'),
    CrisisLine('Samaritans', '116 123', 'Free, 24 hours, every day. Email jo@samaritans.ie.'),
    CrisisLine('Text About It', '50808', 'Text HELLO. Free, 24 hours, a trained volunteer replies.'),
  ], [
    CrisisLine('Emergency', '112 or 999', ''),
  ]),
  'United Kingdom': CountryCrisis('United Kingdom', [
    CrisisLine('Samaritans', '116 123', 'Free, 24 hours, every day.'),
    CrisisLine('NHS urgent mental health help', '111, option 2', 'England and Wales, 24 hours. In Scotland call NHS 24 on 111.'),
    CrisisLine('Shout', '85258', 'Text SHOUT. Free, 24 hours.'),
  ], [
    CrisisLine('Emergency', '999', 'Or go to A&E.'),
  ]),
  'Nigeria': CountryCrisis('Nigeria', [
    CrisisLine('SURPIN suicide prevention helpline', '0800 078 7746', 'Free, 24 hours.'),
    CrisisLine('Mentally Aware Nigeria Initiative', '0809 111 6264', '24 hours, trained volunteers.'),
  ], [
    CrisisLine('Emergency', '112', 'In Lagos also 767.'),
  ]),
  'France': CountryCrisis('France', [
    CrisisLine('Numéro national de prévention du suicide', '3114',
        'Free, 24 hours a day, every day. Answered by nurses and psychologists.'),
  ], [
    CrisisLine('SAMU (medical emergency)', '15', ''),
    CrisisLine('European emergency number', '112', ''),
  ]),
  'Canada': CountryCrisis('Canada', [
    CrisisLine('9-8-8 Suicide Crisis Helpline', '988', 'Call or text. Free, 24/7, in English and French.'),
  ], [
    CrisisLine('Emergency', '911', ''),
  ]),
  'United States': CountryCrisis('United States', [
    CrisisLine('988 Suicide & Crisis Lifeline', '988', 'Call or text. Free, 24/7. Spanish: press 2 or text AYUDA. '
        'Veterans: press 1.'),
    CrisisLine('Crisis Text Line', '741741', 'Text HOME. Free, 24/7, a trained volunteer replies.'),
  ], [
    CrisisLine('Emergency', '911', ''),
  ]),
  'Malaysia': CountryCrisis('Malaysia', [
    CrisisLine('Befrienders KL', '03-7627 2929', '24 hours. English, Malay and Tamil. From abroad: +603-7627 2929.'),
    CrisisLine('Talian HEAL (national mental health line)', '15555', 'Hours vary; the latest source says 8am to midnight.'),
    CrisisLine('Talian Kasih (abuse, family crisis)', '15999', '24 hours. WhatsApp 019-261 5999.'),
  ], [
    CrisisLine('Emergency', '999', ''),
  ]),
  'Thailand': CountryCrisis('Thailand', [
    CrisisLine('Department of Mental Health hotline', '1323', 'Free, 24 hours, in Thai.'),
    CrisisLine('Samaritans of Thailand', '02-113-6789', '12:00 to 22:00. Press 2 for an English call-back.'),
  ], [
    CrisisLine('Medical emergency', '1669', ''),
    CrisisLine('Police', '191', ''),
  ]),
};

/// Lines made for young people, shown when someone says at first start that they are under 18 (Solace is for adults).
/// Countries without a checked line for young people show their crisis lines above, which help people of every age.
const youthLines = <String, List<CrisisLine>>{
  'Canada': [CrisisLine('Kids Help Phone', '1-800-668-6868', 'Call, or text CONNECT to 686868. Free, 24/7, in English '
      'and French.')],
  'Ireland': [CrisisLine('Childline (ISPCC)', '1800 66 66 66', 'Free, 24 hours, for anyone up to 18. Or chat at '
      'childline.ie.')],
  'United Kingdom': [CrisisLine('Childline', '0800 1111', 'Free, 24 hours, for anyone under 19. Or chat at '
      'childline.org.uk.')],
  'United States': [CrisisLine('988 Suicide & Crisis Lifeline', '988', 'Call or text. Free, 24/7, for every age.')],
  'France': [CrisisLine('Fil Santé Jeunes', '0 800 235 236', 'Free and anonymous, every day, for 12 to 25 year olds.')],
};
