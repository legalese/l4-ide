# Preserved from the encoding session's scratchpad on 2026-09-21 so the ditto
# blocks in hsbc-revolution.l4 (the cl.4.2 and cl.7 MCC chains) can be
# regenerated; run: python3 <this file> <which>, see the bottom of the file.
# Emits the two HSBC MCC chains as aligned ditto blocks.
# Rows are transcribed from source/hsbc-revolution-reward-points-tnc.txt in the
# document's OWN row order (cl.4.2 prints 7299, 7399, 7349 out of numeric order;
# that order is preserved deliberately).

EXCLUDED = [  # cl.4.2, 48 rows
 (1,4829,"Money Transfer"),(2,4900,"Utilities - Electric, Gas, Water and Sanitary"),
 (3,5199,"Nondurable Good"),(4,5960,"Direct Marketing - Insurance Services"),
 (5,6010,"Financial Institutions - Manual Cash Disbursements"),
 (6,6011,"Financial Institutions - Automated Cash Disbursements"),
 (7,6012,"Financial Institutions - Merchandise, Services, and Debt Repayment"),
 (8,6050,"Quasi Cash - Customer Financial Institution"),
 (9,6051,"Non-Financial Institutions - Foreign Currency, Non-Fiat Currency, Money Orders, Travelers Cheques, Debt Repayment"),
 (10,6211,"Security Brokers / Dealers"),(11,6300,"Insurance Sales, Underwriting, and Premiums"),
 (12,6513,"Real Estate Agents & Managers - Rentals"),(13,6529,"Remote Stored Value Load - Member"),
 (14,6530,"Remote Stored Value Load - Merchant"),(15,6532,"PSP-Member-Payment Transaction"),
 (16,6533,"PSP-Merchant-Payment Transaction"),(17,6534,"Money Transfer Member"),
 (18,6536,"Moneysend - Intracountry"),(19,6537,"Moneysend - Intercountry"),
 (20,6538,"Moneysend funding"),(21,6540,"Non-Financial Institutions - Stored Value Card Purchase/Load"),
 (22,6555,"Mastercard Imitated Rebate"),(23,7299,"Other Services - Not Elsewhere Classified"),
 (24,7399,"Business Services (Not Elsewhere Classified"),(25,7349,"CLEAN/MAINT/JANITORIAL SERV"),
 (26,7511,"Quasi Cash - Truck Stop Trxns"),(27,7523,"Automobile Parking Lots and Garages"),
 (28,7801,"Government Licensed On-Line Casinos (On-Line Gambling) (US Region only)"),
 (29,7995,"Betting, including Lottery Tickets, Casino Gaming Chips, Off-Track Betting, and Wagers at Race Tracks"),
 (30,8062,"Hospitals"),(31,8211,"Elementary and Secondary Schools"),
 (32,8220,"Colleges, Universities, Professional Schools, and Junior Colleges"),
 (33,8241,"Correspondence Schools"),(34,8244,"Business and Secretarial Schools"),
 (35,8249,"Vocational and Trade Schools"),(36,8299,"Schools and Educational Services (Not Elsewhere Classified)"),
 (37,8398,"Charitable Social Service Organizations"),(38,8651,"Political Organizations"),
 (39,8661,"Religious Organizations"),(40,8999,"Professional Services (Not Elsewhere Classified)"),
 (41,9211,"Court Costs, Including Alimony and Child Support"),(42,9222,"Fines"),
 (43,9223,"Bail and Bond Payments"),(44,9311,"Tax Payments"),
 (45,9399,"Government Services (Not Elsewhere Classified)"),(46,9402,"Postal Services - Government Only"),
 (47,9405,"Intra-Government Purchases - Government Only"),
 (48,9754,"Gambling-Horse Racing Dog Racing State Lotteries"),
]

RETAIL = [  # cl.7 rows 5-42, "Department Stores and Retail Stores"
 (5,4816,"Computer Network/Information Services"),(6,5045,"Computers, Computer Peripheral Equipment, Software"),
 (7,5262,"Marketplaces"),(8,5309,"Duty Free Stores"),(9,5310,"Discount Stores"),
 (10,5311,"Department Stores"),(11,5331,"Variety Stores"),(12,5399,"Miscellaneous General Merchandise Stores"),
 (13,5611,"Men's and Boys' Clothing and Accessories Stores"),(14,5621,"Women's Ready to Wear Stores"),
 (15,5631,"Women's Accessory and Specialty Stores"),(16,5641,"Children's and Infants' Wear Stores"),
 (17,5651,"Family Clothing Stores"),(18,5655,"Sports Apparel, and Riding Apparel Stores"),
 (19,5661,"Shoe Stores"),(20,5691,"Men's and Women's Clothing Stores"),
 (21,5699,"Accessory and Apparel Stores - Miscellaneous"),(22,5732,"Electronics Sales"),
 (23,5733,"Music Stores - Musical Instruments, Pianos and Sheet Music"),(24,5734,"Computer Software Stores"),
 (25,5735,"Record Shops"),(26,5912,"Drug Stores and Pharmacies"),(27,5942,"Book Stores"),
 (28,5944,"Clock, Jewelry, Watch and Silverware Stores"),(29,5945,"Game, Toy and Hobby Shops"),
 (30,5946,"Camera and Photographic Supply Stores"),(31,5947,"Card, Gift, Novelty and Souvenir Shops"),
 (32,5948,"Leather Goods and Luggage Stores"),(33,5949,"Fabric, Needlework, Piece Goods and Sewing Stores"),
 (34,5964,"Direct Marketing - Catalog Merchants"),(35,5965,"Direct Marketing - Combination Catalog and Retail Merchant"),
 (36,5966,"Direct Marketing - Outbound Telemarketing Merchants"),(37,5967,"Direct Marketing - Inbound Telemarketing Merchants"),
 (38,5968,"Direct Marketing - Continuity/Subscription Merchants"),(39,5969,"Direct Marketing - Other Direct Marketers - Not Elsewhere Classified"),
 (40,5970,"Artist Supply Stores, Craft Shops"),(41,5992,"Florists"),(42,5999,"Miscellaneous and Specialty Retail Stores"),
]

DINING = [  # cl.7 rows 43-47, "Dining excluding hotel dining"
 (43,5441,"Candy, Nut and Confectionery Stores"),(44,5462,"Bakeries"),(45,5811,"Caterers"),
 (46,5812,"Eating Places and Restaurants"),
 (47,5813,"Bars, Cocktail Lounges, Discotheques, Nightclubs and Taverns - Drinking Places (Alcoholic Beverages)"),
]

OTHERS = [  # cl.7 rows 48-49, "Others such as Transportation and Membership Clubs"
 (48,4121,"Taxicabs and Limousines"),
 (49,7997,"Clubs - Country Clubs, Membership (Athletic, Recreation, Sports), Private Golf Courses"),
]

def chain(rows, indent=4, commentcol=32):
    """First row writes `mcc EQUALS nnnn`; later rows ditto both tokens under it."""
    out = []
    lead_first = " " * (indent + 3)          # aligns `mcc` under the `OR` rows
    lead_rest  = " " * indent + "OR "
    for i, (n, mcc, desc) in enumerate(rows):
        if i == 0:
            body = "mcc EQUALS %d" % mcc
            line = lead_first + body
        else:
            body = "^   ^      %d" % mcc     # ^ pads `mcc` (3) and `EQUALS` (6)
            line = lead_rest + body
        line = line.ljust(commentcol) + "-- %2d  %s" % (n, desc)
        out.append(line.rstrip())
    return "\n".join(out)

import sys
which = sys.argv[1]
print(chain({"excluded": EXCLUDED, "retail": RETAIL, "dining": DINING, "others": OTHERS}[which]))
